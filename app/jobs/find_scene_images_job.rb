# Plans a picture search for each scene with a single planner call, gathers the pictures of the
# Wikipedia articles named, then gives each scene its candidates: its own articles' pictures and
# keyword search results, scored in code (Media::CandidateScore) so only the few that fit are checked.
# A mood scene ("the years passed") with nothing that fits gets filler footage; a scene about a real
# subject gets an AI image suggested, with filler footage until it is made. Storyboard projects
# ("Create video") already have their scenes, laid out from the script; older projects split the
# confirmed narration into scenes here. The planner runs only when the script or the narration
# length has changed, so repeated clicks don't pay for the same plan twice.
class FindSceneImagesJob < ApplicationJob
  queue_as :default

  MAX_CANDIDATES = 5
  # Candidates gathered per scene for scoring.
  POOL_SIZE = 12
  # The best-scored candidates kept per scene: the picture check looks at these and no more.
  MAX_CHECKED = 4
  # Scenes with no specific subject to show, which filler footage can carry.
  MOOD_SUBJECTS = %w[abstract generic_scene].freeze
  FILLER_NOTE = "Filler footage: this scene has no specific subject to show.".freeze
  MAX_SEARCHES_PER_SCENE = 6
  # How the pool is shared: the scene's own articles' pictures, keyword search results and other library
  # pictures, so one big article can't crowd out what a search finds. Places one source can't fill go
  # to the others.
  POOL_SHARES = { own: 6, searched: 4, matched: 2 }.freeze
  # Scenes the picture scout searches per run, which caps its cost (about 1-2 cents a scene).
  MAX_SCOUTED = 10
  RESEARCH_PICTURES_PER_ARTICLE = 6
  # Opening on footage holds viewers better than a still, so the first scenes look for video first.
  HOOK_SCENES = 2
  MAX_VIDEOS = 2
  MAX_VIDEO_SEARCHES = 3
  # Scenes Pixabay footage may serve: present-day footage can show a place or a mood, not a past moment.
  PIXABAY_VIDEO_SUBJECTS = %w[real_place generic_scene abstract].freeze
  PLANNING_FAILED = "Scene planning failed. Create scene again to retry.".freeze

  # Fetches each article's pictures once per run, so the library can be built from the research
  # before planning and again after it without asking Wikipedia twice. An article's pictures are the
  # ones it shows, then the rest of its Commons category, which is often several times bigger.
  class CachedArticleImages
    def initialize(fetcher = Media::WikipediaArticleImages.new, categories = Media::CommonsCategoryImages.new)
      @fetcher = fetcher
      @categories = categories
      @cache = {}
    end

    def images(article)
      @cache.fetch(article) { @cache[article] = (@fetcher.images(article) + category_images(article)).uniq(&:image_url) }
    end

    # The search for videos in the article's Commons category, or nil.
    def video_query(article)
      @categories.video_query(article)
    rescue Media::Error => e
      Rails.logger.warn("Commons category of #{article.inspect} could not be read: #{e.message}")
      nil
    end

    private
      # A category that can't be read leaves the article's own pictures.
      def category_images(article)
        @categories.images(article)
      rescue Media::Error => e
        Rails.logger.warn("Commons category of #{article.inspect} could not be read: #{e.message}")
        []
      end
  end

  def perform(project)
    track = project.voice_track
    unless project.storyboard? || track&.confirmed?
      raise Ai::Error, "Confirm the voice before finding scene images."
    end

    @article_images = CachedArticleImages.new
    prepare_scenes(project, track)
    # Reload: the association still holds the scenes built before planning added their queries.
    scenes = project.scenes.reload
    if project.image_mode == "ai_all"
      scenes.each { |scene| suggest_ai(scene, "AI images were chosen for every scene.") }
    else
      @library = build_library(project, scenes)
      scenes.each { |scene| find_images(scene) }
      check_pictures(project)
      second_chance(project)
      fill_waiting_scenes(project)
    end
  ensure
    project.update!(settings: project.settings.except("scenes_searching"))
    Turbo::StreamsChannel.broadcast_refresh_to([ project, :scenes ])
  end

  private
    # Identifies "this script at this length". Scenes and plans are reused while it stays the same.
    # A storyboard's scenes come from the script alone.
    def scene_key(project, track)
      return Digest::SHA256.hexdigest(project.latest_script.digest) if project.storyboard?

      Digest::SHA256.hexdigest("#{project.latest_script.digest}:#{track.duration_ms}")
    end

    def prepare_scenes(project, track)
      key = scene_key(project, track)
      return if project.settings["scene_key"] == key && project.scenes.exists?

      split_scenes(project, track) unless project.storyboard?
      return unless plan_scenes(project)

      project.update!(settings: project.settings.merge("scene_key" => key))
    end

    def split_scenes(project, track)
      Scene.transaction do
        project.scenes.destroy_all
        NarrationScenes.new(project.latest_script.body, track.duration_ms).scenes.each do |scene|
          project.scenes.create!(position: scene.position, text: scene.text, start_ms: scene.start_ms,
                                 duration_ms: scene.duration_ms)
        end
      end
    end

    # One planning call for the whole project. Returns false if planning failed.
    def plan_scenes(project)
      scenes = project.scenes.order(:position).to_a
      result, facts = plan_with_director(project, scenes)
      unless result
        research = project.settings["research"].presence unless project.image_mode == "ai_all"
        result = Ai::ScenePlanner.new.call(topic: project.prompt, scenes: scenes, research: research,
                                           pictures: research ? research_pictures(research) : [])
        record_usage(project, result, "scene_plan")
        facts = Array(research && research["facts"])
      end
      project.update!(settings: project.settings.merge("topic_depiction" => result.topic_depiction,
                                                       "articles" => result.articles, "facts" => facts || []))

      scenes.each do |scene|
        plan = result.plans.fetch(scene.position)
        scene.update!(search_query: plan.search_queries.first, plan: plan.to_h.except(:position))
      end
      true
    rescue Ai::OutOfCredits
      raise
    rescue Ai::Error => e
      Rails.logger.warn("Scene planning failed for project #{project.id}: #{e.message}")
      scenes&.each { |scene| scene.update!(search_error: PLANNING_FAILED) }
      false
    end

    # A project researched before its script is planned by the cheap scene planner from that research
    # (and the pictures its articles have). One without research has the Director research the real
    # history and plan. If the Director fails, the cheap planner plans from the narration alone; it
    # also plans alone when every scene will be an AI image.
    def plan_with_director(project, scenes)
      return unless Ai::Director.enabled? && project.image_mode != "ai_all" && project.settings["research"].blank?

      plan = Ai::Director.new.plan(topic: project.prompt, scenes: scenes)
      record_usage(project, plan.result, "director_plan")
      if plan.dropped_articles.any?
        Rails.logger.info("Director named articles that don't exist for project #{project.id}: #{plan.dropped_articles.inspect}")
      end
      [ plan.result, plan.facts ]
    rescue Ai::OutOfCredits
      raise
    rescue Ai::Error => e
      Rails.logger.warn("Director planning failed for project #{project.id}: #{e.message}; using the scene planner")
      nil
    end

    def record_usage(project, result, operation)
      project.api_usages.create!(provider: Ai::TextGenerator::PROVIDER, operation: operation,
                                 units: result.total_tokens, cost_usd: result.cost_usd)
    end

    # One fetch per article for the whole video; costs nothing but a second per article.
    def build_library(project, scenes)
      articles = Array(project.settings["articles"]) + Array(project.settings.dig("research", "articles")) +
                 scenes.flat_map { |scene| Array(scene.plan["articles"]) }
      Media::ArticleLibrary.build(articles, fetcher: @article_images)
    end

    # What the research articles can show, as short lines for the scene plan: a few from each
    # article, so every article is represented.
    def research_pictures(research)
      library = Media::ArticleLibrary.build(Array(research["articles"]), fetcher: @article_images)
      library.by_article.values.flat_map { |items| items.first(RESEARCH_PICTURES_PER_ARTICLE) }.map do |item|
        title = CGI.unescape(item.page_url.to_s[/File:(.+)\z/, 1].to_s).tr("_", " ").sub(/\.\w+\z/, "")
        [ title, (item.taken_on.presence && "taken #{item.taken_on}"), "article: #{item.source_article}" ].compact.join("; ")
      end
    end

    # use_library: false for the second chance, whose scenes already saw (and rejected) the library.
    def find_images(scene, use_library: true)
      # Without a plan there is nothing to search for. The error was set when planning failed.
      if scene.search_query.blank?
        scene.update!(search_error: "No search terms for this scene. Create scene again to retry.") if scene.search_error.blank?
        return
      end

      videos = wants_video?(scene) ? video_candidates_for(scene) : []
      images =
        begin
          candidates_for(scene, use_library: use_library)
        rescue Media::Error
          raise if videos.empty?

          []
        end

      store_candidates(scene, videos, images)
      scene.update!(search_error: nil)
    rescue Media::Error => e
      Rails.logger.warn("Image search failed for scene #{scene.id}: #{e.message}")
      scene.update!(search_error: "Image search failed. Try again later.")
    end

    # Looks at each scene's best candidates and keeps one only if it truly fits. A scene with none
    # gets its sourced picture deselected and an AI image suggested, so nothing unchecked reaches
    # the video. The user's own uploads and AI images are left alone.
    def check_pictures(project, only: nil)
      verifier = Ai::ImageVerifier.new
      all_scenes = project.scenes.includes(:images).to_a
      # A picture is used once per video: pictures other scenes already show can't be picked again.
      used = all_scenes.filter_map { |scene| scene.selected_image&.image_url if scene.media_check.in?(%w[verified chosen]) }
      scenes = only ? all_scenes.select { |scene| only.map(&:id).include?(scene.id) } : all_scenes
      scenes.each do |scene|
        next if scene.selected_image&.stored_file?

        used.delete(scene.selected_image&.image_url) if scene.media_check.in?(%w[verified chosen])
        candidates = scene.images.reject { |media| media.stored_file? || used.include?(media.image_url) }
                              .sort_by { |media| media.selected? ? 0 : 1 }
        if candidates.empty?
          next use_filler(project, scene, FILLER_NOTE) if mood_scene?(scene)

          next suggest_ai(scene, scene.search_error.presence || "No free picture fits this scene.")
        end

        chosen = check_scene(project, scene, candidates, verifier)
        used << chosen.image_url if chosen
      end
    end

    def check_scene(project, scene, candidates, verifier)
      result = verifier.call(scene: scene, candidates: candidates)
      project.api_usages.create!(provider: Ai::TextGenerator::PROVIDER, operation: "image_check",
                                 units: result.total_tokens, cost_usd: result.cost_usd)

      chosen = candidates.find { |media| media.id == result.choice_id }
      # A scene about a revered figure never shows a face, whatever else the check thought of the picture.
      if chosen && result.faces && scene.depiction != "normal"
        suggest_ai(scene, "The best real picture shows faces, which this video avoids for revered figures.")
        return nil
      end

      if chosen
        chosen.select!
        scene.update!(media_check: "verified", media_note: result.reason, search_error: nil)
        chosen
      elsif mood_scene?(scene)
        use_filler(project, scene, FILLER_NOTE)
        nil
      else
        suggest_ai(scene, "No real picture fits. #{result.reason}".strip)
        nil
      end
    rescue Ai::OutOfCredits
      raise
    rescue Ai::Error => e
      Rails.logger.warn("Picture check failed for scene #{scene.id}: #{e.message}")
      scene.update!(media_check: nil, media_note: "The picture check failed. Review this scene yourself.")
      nil
    end

    # Scenes still without a picture get a search agent of their own (Ai::PictureScout), hook scenes
    # first and at most MAX_SCOUTED per run. Its choice is checked like any other candidate; scenes it
    # finds nothing for keep their AI suggestion.
    def second_chance(project)
      waiting = project.scenes.reload.select { |scene| scene.ai_suggested? && scene.images.none?(&:stored_file?) }
      return if waiting.empty?

      scout = Ai::PictureScout.new(articles: @article_images)
      verifier = Ai::ImageVerifier.new
      used = project.scenes.filter_map { |scene| scene.selected_image&.image_url }
      waiting.first(MAX_SCOUTED).each do |scene|
        chosen = scout_scene(project, scene, scout, verifier, used)
        used << chosen.image_url if chosen
      end
    end

    def scout_scene(project, scene, scout, verifier, used)
      result = scout.call(scene: scene, used_urls: used)
      project.api_usages.create!(provider: Ai::PictureScout::PROVIDER, operation: "picture_scout",
                                 units: result.total_tokens, cost_usd: result.cost_usd)
      return unless result.choice

      found = result.choice
      media = scene.images.create!(provider: found.provider, image_url: found.image_url, page_url: found.page_url,
                                   credit: found.credit, license: found.license, description: found.description,
                                   taken_on: found.taken_on, categories: found.categories, source_article: found.source_article)
      check_scene(project, scene, [ media ], verifier)
    rescue Ai::OutOfCredits
      raise
    rescue Ai::Error => e
      Rails.logger.warn("Picture scout failed for scene #{scene.id}: #{e.message}")
      nil
    end

    def mood_scene?(scene)
      MOOD_SUBJECTS.include?(scene.plan["subject_type"])
    end

    # Selects filler footage for the scene. With a note, the filler is the scene's picture (a mood
    # scene); without one, it only stands in until the suggested AI image is made.
    def use_filler(project, scene, note = nil)
      used = project.scenes.includes(:images).filter_map { |other| other.selected_image&.image_url }
      historical = Media::Fillers.historical?(project.prompt, scene.text, *Array(project.settings.dig("research", "facts")))
      clip = Media::Fillers.new.pick([ scene.text, scene.plan["visual_intent"] ].join(" "), used_urls: used, historical: historical)
      return unless clip

      scene.images.where(selected: true).update_all(selected: false)
      scene.images.create!(provider: clip.provider, media_type: "video", image_url: clip.video_url, poster_url: clip.poster_url,
                           page_url: clip.page_url, credit: clip.credit, license: clip.license, duration_ms: clip.duration_ms,
                           description: clip.description, selected: true,
                           clip_start_ms: SceneImage.default_clip_start(clip.duration_ms, scene.duration_ms))
      scene.update!(media_check: "filler", media_note: note, search_error: nil) if note
    end

    # Scenes still waiting for an AI image show filler footage meanwhile, so the storyboard has no
    # gaps and can be approved before every AI image is made. Scenes whose planning failed stay
    # empty, so the retry message isn't hidden.
    def fill_waiting_scenes(project)
      waiting = project.scenes.includes(:images).select do |scene|
        scene.ai_suggested? && scene.selected_image.nil? && scene.search_error != PLANNING_FAILED
      end
      waiting.each { |scene| use_filler(project, scene) }
    end

    def suggest_ai(scene, note)
      scene.images.where(selected: true).reject(&:stored_file?).each { |media| media.update!(selected: false) }
      scene.update!(media_check: "ai_suggested", media_note: note)
    end

    # Hook scenes, scenes the plan marks for video, and, when Pixabay is on, scenes about a real place,
    # where present-day footage of the place (a coast, a valley from the air) carries the scene.
    def wants_video?(scene)
      scene.position <= HOOK_SCENES || scene.plan["prefer"] == "video" ||
        (pixabay_key.present? && scene.plan["subject_type"] == "real_place")
    end

    # Videos first, so a found video becomes the selected candidate. Only earlier search results are
    # replaced: the user's uploads and AI images stay, and a selected one keeps its place.
    def store_candidates(scene, videos, images)
      SceneImage.transaction do
        scene.images.where.not(provider: [ SceneImage::UPLOAD_PROVIDER, SceneImage::AI_PROVIDER ]).destroy_all
        select_new = !scene.images.exists?(selected: true)

        videos.each_with_index do |video, index|
          scene.images.create!(provider: video.provider, media_type: "video", image_url: video.video_url,
                               poster_url: video.poster_url, page_url: video.page_url, credit: video.credit,
                               license: video.license, duration_ms: video.duration_ms, description: video.description,
                               taken_on: video.taken_on, categories: video.categories,
                               clip_start_ms: SceneImage.default_clip_start(video.duration_ms, scene.duration_ms),
                               selected: select_new && index.zero?)
        end
        images.each_with_index do |image, index|
          scene.images.create!(provider: image.provider, image_url: image.image_url, page_url: image.page_url,
                               credit: image.credit, license: image.license, description: image.description,
                               taken_on: image.taken_on, categories: image.categories, source_article: image.source_article,
                               selected: select_new && videos.empty? && index.zero?)
        end
      end
    end

    # Video is a bonus: a scene without a good video keeps its images. Footage filed in the Commons
    # category of the scene's own articles comes first. Otherwise only the planner's own queries are
    # used (broadened ones pull in unrelated footage), and a video's title must share a real word with
    # the query, because Wikimedia matches words anywhere in a file's description. Pixabay's present-day
    # footage comes last, and only for places and moods, never for a historical event, person or object.
    def video_candidates_for(scene)
      category_videos(scene).presence || keyword_videos(scene).presence || pixabay_videos(scene)
    end

    # The plan's queries from broad to specific: the broad ones (usually the place's name) find footage
    # of the place itself, and every word of the query must be in a clip's tags.
    def pixabay_videos(scene)
      return [] unless pixabay_key.present? && PIXABAY_VIDEO_SUBJECTS.include?(scene.plan["subject_type"])

      queries = [ scene.search_query, *scene.plan["search_queries"] ].compact_blank.uniq.reverse.first(MAX_VIDEO_SEARCHES)
      queries.each do |query|
        videos = Media::PixabayVideoSearch.new(api_key: pixabay_key).search(query, limit: MAX_VIDEOS)
        return videos if videos.any?
      rescue Media::Error => e
        Rails.logger.warn("Pixabay video search failed for scene #{scene.id}: #{e.message}")
      end
      []
    end

    def pixabay_key
      ENV["PIXABAY_API_KEY"].presence
    end

    def category_videos(scene)
      Array(scene.plan["articles"]).each do |article|
        query = @article_images&.video_query(article)
        next unless query

        videos = Media::CommonsVideoSearch.new.search(query, limit: MAX_VIDEOS)
        return videos if videos.any?
      rescue Media::Error => e
        Rails.logger.warn("Category video search failed for scene #{scene.id}: #{e.message}")
      end
      []
    end

    def keyword_videos(scene)
      queries = [ scene.search_query, *scene.plan["search_queries"] ].compact_blank.uniq.first(MAX_VIDEO_SEARCHES)
      queries.each do |query|
        videos = Media::CommonsVideoSearch.new.search(query, limit: MAX_VIDEOS * 3).select { |video| relevant_title?(video.title, query) }
        return videos.first(MAX_VIDEOS) if videos.any?
      rescue Media::Error => e
        Rails.logger.warn("Video search failed for scene #{scene.id}: #{e.message}")
      end
      []
    end

    # Shares words of 4+ letters with the query, compared on the first 5 letters ("flights" ~ "flight"):
    # two of them when the query has two, since one common word lets in footage from anywhere
    # ("Inbound train at Science Park portal, 2020" for "Atlantic Avenue Elevated train").
    def relevant_title?(title, query)
      stems = ->(text) { text.downcase.scan(/[[:alpha:]]{4,}/).reject { |word| Scene::STOPWORDS.include?(word) }.map { |word| word.first(5) }.uniq }
      wanted = stems.call(query)
      wanted.any? && (stems.call(title) & wanted).size >= [ wanted.size, 2 ].min
    end

    # The pool: the best of the scene's own articles' pictures (the article and its Commons category),
    # what the keyword search finds, and other library pictures that share words with what the scene
    # should show, in the shares of POOL_SHARES. The search always runs, because even a big library
    # can miss the moment a scene needs. Only the best-scored few are kept for the picture check.
    def candidates_for(scene, use_library: true)
      planned = [ scene.search_query, *scene.plan["search_queries"] ].compact_blank.uniq { |query| query.downcase }
      own, matched = use_library ? library_candidates(scene, planned) : [ [], [] ]
      searched = searched_candidates(scene, planned, own.size + matched.size)

      shares = own.first(POOL_SHARES[:own]) + searched.first(POOL_SHARES[:searched]) + matched.first(POOL_SHARES[:matched])
      pool = (shares + own + searched + matched).uniq(&:image_url).first(POOL_SIZE)
      Media::CandidateScore.new(scene, common_words: @library&.common_words || []).best(pool, limit: MAX_CHECKED)
    end

    # [own, matched]: the scene's own articles' pictures, best match first, and other library pictures
    # sharing words with the scene.
    def library_candidates(scene, planned)
      return [ [], [] ] if @library.nil? || @library.empty?

      text = [ scene.plan["visual_intent"], *planned ].join(" ")
      own = @library.for_articles(scene.plan["articles"], text)
      [ own, @library.matching(text) - own ]
    end

    # Searches the planner's first query always, the others while the pool is short, then broader
    # forms of them only if it is still small. A failed search moves on; the scene only reports an
    # error if every search failed and the library gave nothing either.
    def searched_candidates(scene, planned, found)
      broader = Media::QueryVariants.for(planned, limit: MAX_SEARCHES_PER_SCENE, topic: scene.project.prompt) - planned
      results = []
      last_error = nil

      (planned + broader).first(MAX_SEARCHES_PER_SCENE).each_with_index do |query, index|
        break if index.positive? && found + results.size >= POOL_SIZE
        next if broader.include?(query) && found + results.size >= MAX_CANDIDATES

        begin
          results = (results + search_sources(query, POOL_SIZE / 2)).uniq(&:image_url)
        rescue Media::Error => e
          last_error = e
        end
      end
      raise last_error if results.empty? && found.zero? && last_error

      results
    end

    def search_sources(query, limit)
      results = Media::CommonsSearch.new.search(query, limit: limit)
      if pixabay_key && results.size < limit
        results += Media::PixabaySearch.new(api_key: pixabay_key).search(query, limit: limit - results.size)
      end
      results
    end
end
