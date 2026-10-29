# Plans a picture search for each scene with a single planner call, gathers the pictures of the
# Wikipedia articles named, then gives each scene its candidates: its own articles' pictures first,
# keyword search only when those run short. Storyboard projects ("Create video") already have their
# scenes, laid out from the script; older projects split the confirmed narration into scenes here. The planner runs only when the script or the
# narration length has changed, so repeated clicks don't pay for the same plan twice.
class FindSceneImagesJob < ApplicationJob
  queue_as :default

  MAX_CANDIDATES = 5
  # Candidates gathered per scene for the relevance check to choose from.
  POOL_SIZE = 12
  NO_MATCH = "No matching free image found. Search again, upload one, or generate one with AI.".freeze
  MAX_SEARCHES_PER_SCENE = 6
  # Opening on footage holds viewers better than a still, so the first scenes look for video first.
  HOOK_SCENES = 2
  MAX_VIDEOS = 2
  MAX_VIDEO_SEARCHES = 3
  PLANNING_FAILED = "Scene planning failed. Create scene again to retry.".freeze

  # Fetches each article's pictures once per run, so the library can be built from the research
  # before planning and again after it without asking Wikipedia twice.
  class CachedArticleImages
    def initialize(fetcher = Media::WikipediaArticleImages.new)
      @fetcher = fetcher
      @cache = {}
    end

    def images(article)
      @cache.fetch(article) { @cache[article] = @fetcher.images(article) }
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
      rank_candidates(project)
      check_pictures(project)
      second_chance(project)
      review_storyboard(project)
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
        result = Ai::ScenePlanner.new.call(topic: project.prompt, scenes: scenes)
        record_usage(project, result, "scene_plan")
      end
      project.update!(settings: project.settings.merge("topic_depiction" => result.topic_depiction,
                                                       "articles" => result.articles, "facts" => facts || []))

      scenes.each do |scene|
        plan = result.plans.fetch(scene.position)
        scene.update!(search_query: plan.search_queries.first, plan: plan.to_h.except(:position))
      end
      true
    rescue Ai::Error => e
      Rails.logger.warn("Scene planning failed for project #{project.id}: #{e.message}")
      scenes&.each { |scene| scene.update!(search_error: PLANNING_FAILED) }
      false
    end

    # The Director researches the real history and plans when real pictures are wanted. If it fails,
    # the cheap scene planner plans instead; it also plans alone when every scene will be an AI image.
    def plan_with_director(project, scenes)
      return unless Ai::Director.enabled? && project.image_mode != "ai_all"

      research = project.settings["research"].presence
      pictures = research ? research_pictures(research) : []
      plan = Ai::Director.new.plan(topic: project.prompt, scenes: scenes, research: research, pictures: pictures)
      record_usage(project, plan.result, "director_plan")
      if plan.dropped_articles.any?
        Rails.logger.info("Director named articles that don't exist for project #{project.id}: #{plan.dropped_articles.inspect}")
      end
      [ plan.result, plan.facts ]
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

    # What the research articles can show, as short lines for the Director's plan.
    def research_pictures(research)
      library = Media::ArticleLibrary.build(Array(research["articles"]), fetcher: @article_images)
      library.items.map do |item|
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

    # One relevance check for the whole project. Candidates it rejects are removed, the best kept one
    # is selected, and a scene with none left asks the user to step in. If the check fails, the
    # scenes keep their unranked candidates.
    def rank_candidates(project, only: nil)
      scenes = project.scenes.includes(:images).select { |scene| scene.images.any? { |media| !media.stored_file? } }
      scenes = scenes.select { |scene| only.map(&:id).include?(scene.id) } if only
      return if scenes.empty?

      result = Ai::CandidateRanker.new.call(topic: project.prompt, scenes: scenes)
      project.api_usages.create!(provider: Ai::TextGenerator::PROVIDER, operation: "candidate_rank",
                                 units: result.total_tokens, cost_usd: result.cost_usd)
      scenes.each { |scene| apply_ranking(scene, result.kept.fetch(scene.position, [])) }
    rescue Ai::Error => e
      Rails.logger.warn("Candidate check failed for project #{project.id}: #{e.message}")
    end

    def apply_ranking(scene, kept_ids)
      SceneImage.transaction do
        scene.images.reject { |media| media.stored_file? || kept_ids.include?(media.id) }.each(&:destroy!)
        scene.images.reset
        best = scene.images.find { |media| media.id == kept_ids.first }
        if best
          best.select!
          scene.update!(search_error: nil)
        elsif scene.images.none?
          scene.update!(search_error: NO_MATCH)
        end
      end
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
        next suggest_ai(scene, scene.search_error.presence || "No free picture was found.") if candidates.empty?

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
      else
        suggest_ai(scene, "No real picture fits. #{result.reason}".strip)
        nil
      end
    rescue Ai::Error => e
      Rails.logger.warn("Picture check failed for scene #{scene.id}: #{e.message}")
      scene.update!(media_check: nil, media_note: "The picture check failed. Review this scene yourself.")
      nil
    end

    # Scenes still without a picture get new, archive-style queries (one call for all of them), and are
    # searched, ranked and checked once more. Scenes that still find nothing keep their AI suggestion.
    def second_chance(project)
      waiting = project.scenes.reload.select { |scene| scene.ai_suggested? && scene.images.none?(&:stored_file?) }
      return if waiting.empty?

      result = Ai::QueryRewriter.new.call(topic: project.prompt, scenes: waiting)
      project.api_usages.create!(provider: Ai::TextGenerator::PROVIDER, operation: "query_rewrite",
                                 units: result.total_tokens, cost_usd: result.cost_usd)

      retried = waiting.select do |scene|
        queries = result.queries.fetch(scene.position, [])
        next false if queries.empty?

        scene.update!(search_query: queries.first, search_error: nil, media_check: nil, media_note: nil,
                      plan: scene.plan.merge("search_queries" => queries))
        find_images(scene, use_library: false)
        true
      end
      return if retried.empty?

      rank_candidates(project, only: retried)
      check_pictures(project, only: retried)
    rescue Ai::Error => e
      Rails.logger.warn("Second-chance search failed for project #{project.id}: #{e.message}")
    end

    # The Director looks at the whole storyboard once. A rejected picture makes way for an AI image
    # (with the Director's prompt), and a swapped-in candidate must still pass the picture check.
    # Scenes the user decided are left alone.
    def review_storyboard(project)
      return unless Ai::Director.enabled?

      scenes = project.scenes.reload.includes(:images).order(:position).to_a
      fixed = scenes.select { |scene| user_decided?(scene) }.map(&:position)
      review = Ai::Director.new.review(topic: project.prompt, scenes: scenes, facts: project.settings["facts"], fixed: fixed)
      record_usage(project, review, "director_review")

      verifier = Ai::ImageVerifier.new
      scenes.each do |scene|
        decision = review.decisions[scene.position]
        next if decision.nil? || fixed.include?(scene.position)

        scene.update!(plan: scene.plan.merge("ai_prompt" => decision.ai_prompt)) if decision.ai_prompt
        case decision.action
        when "reject" then suggest_ai(scene, "Director: #{decision.note}") if scene.selected_image
        when "swap" then swap_picture(project, scene, decision, verifier)
        end
      end
    rescue Ai::Error => e
      Rails.logger.warn("Storyboard review failed for project #{project.id}: #{e.message}")
    end

    def user_decided?(scene)
      scene.media_check == "chosen" || scene.selected_image&.stored_file?
    end

    # The Director asked for this candidate because the current picture is wrong, so if the
    # candidate fails the check (or another scene shows it), the scene waits for an AI image.
    def swap_picture(project, scene, decision, verifier)
      candidate = scene.images.find { |media| media.id == decision.candidate_id }
      shown_elsewhere = SceneImage.where(scene: project.scenes, selected: true).where.not(scene_id: scene.id).pluck(:image_url)
      if candidate.nil? || candidate.stored_file? || shown_elsewhere.include?(candidate.image_url)
        return suggest_ai(scene, "Director: #{decision.note}")
      end

      result = verifier.call(scene: scene, candidates: [ candidate ])
      project.api_usages.create!(provider: Ai::TextGenerator::PROVIDER, operation: "image_check",
                                 units: result.total_tokens, cost_usd: result.cost_usd)
      if result.choice_id == candidate.id && !(result.faces && scene.depiction != "normal")
        candidate.select!
        scene.update!(media_check: "verified", media_note: "Director: #{decision.note}", search_error: nil)
      else
        suggest_ai(scene, "Director: #{decision.note} The replacement didn't pass the picture check.")
      end
    rescue Ai::Error => e
      Rails.logger.warn("Checking the Director's swap failed for scene #{scene.id}: #{e.message}")
      suggest_ai(scene, "Director: #{decision.note}")
    end

    def suggest_ai(scene, note)
      scene.images.where(selected: true).reject(&:stored_file?).each { |media| media.update!(selected: false) }
      scene.update!(media_check: "ai_suggested", media_note: note)
    end

    def wants_video?(scene)
      scene.position <= HOOK_SCENES || scene.plan["prefer"] == "video"
    end

    # Videos first, so a found video becomes the selected candidate.
    def store_candidates(scene, videos, images)
      SceneImage.transaction do
        scene.images.destroy_all
        videos.each_with_index do |video, index|
          scene.images.create!(provider: video.provider, media_type: "video", image_url: video.video_url,
                               poster_url: video.poster_url, page_url: video.page_url, credit: video.credit,
                               license: video.license, duration_ms: video.duration_ms, description: video.description,
                               taken_on: video.taken_on, categories: video.categories,
                               clip_start_ms: SceneImage.default_clip_start(video.duration_ms, scene.duration_ms),
                               selected: index.zero?)
        end
        images.each_with_index do |image, index|
          scene.images.create!(provider: image.provider, image_url: image.image_url, page_url: image.page_url,
                               credit: image.credit, license: image.license, description: image.description,
                               taken_on: image.taken_on, categories: image.categories, source_article: image.source_article,
                               selected: videos.empty? && index.zero?)
        end
      end
    end

    # Video is a bonus: a scene without a good video keeps its images. Only the planner's own
    # queries are used (broadened ones pull in unrelated footage), and a video's title must share
    # a real word with the query, because Wikimedia matches words anywhere in a file's description.
    def video_candidates_for(scene)
      queries = [ scene.search_query, *scene.plan["search_queries"] ].compact_blank.uniq.first(MAX_VIDEO_SEARCHES)
      queries.each do |query|
        videos = Media::CommonsVideoSearch.new.search(query, limit: MAX_VIDEOS * 3).select { |video| relevant_title?(video.title, query) }
        return videos.first(MAX_VIDEOS) if videos.any?
      rescue Media::Error => e
        Rails.logger.warn("Video search failed for scene #{scene.id}: #{e.message}")
      end
      []
    end

    # Shares a word of 4+ letters with the query, compared on the first 5 letters ("flights" ~ "flight").
    def relevant_title?(title, query)
      stems = ->(text) { text.downcase.scan(/[[:alpha:]]{4,}/).reject { |word| Scene::STOPWORDS.include?(word) }.map { |word| word.first(5) } }
      (stems.call(title) & stems.call(query)).any?
    end

    # The pool starts with the library: pictures from the scene's own articles, then library pictures
    # that share words with what the scene should show. Keyword search fills in only when that is
    # short, because it brings back mostly unrelated files. The relevance check chooses from the pool.
    def candidates_for(scene, use_library: true)
      planned = [ scene.search_query, *scene.plan["search_queries"] ].compact_blank.uniq { |query| query.downcase }
      results = use_library ? library_candidates(scene, planned) : []
      return results if results.size >= MAX_CANDIDATES

      (results + searched_candidates(scene, planned, results.size)).uniq(&:image_url).first(POOL_SIZE)
    end

    def library_candidates(scene, planned)
      return [] if @library.nil? || @library.empty?

      own = @library.for_articles(scene.plan["articles"])
      matched = @library.matching([ scene.plan["visual_intent"], *planned ].join(" "))
      (own + matched).uniq(&:image_url).first(POOL_SIZE)
    end

    # Searches all of the planner's queries (the first hits of one query are often not the best), then
    # broader forms of them only if the pool is still small. A failed search moves on; the scene only
    # reports an error if every search failed and the library gave nothing either.
    def searched_candidates(scene, planned, found)
      broader = Media::QueryVariants.for(planned, limit: MAX_SEARCHES_PER_SCENE, topic: scene.project.prompt) - planned
      results = []
      last_error = nil

      (planned + broader).first(MAX_SEARCHES_PER_SCENE).each do |query|
        break if found + results.size >= POOL_SIZE
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
      pixabay_key = ENV["PIXABAY_API_KEY"].presence
      if pixabay_key && results.size < limit
        results += Media::PixabaySearch.new(api_key: pixabay_key).search(query, limit: limit - results.size)
      end
      results
    end
end
