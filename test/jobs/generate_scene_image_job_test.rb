require "test_helper"

class GenerateSceneImageJobTest < ActiveJob::TestCase
  class FakeGenerator
    def initialize(error: nil)
      @error = error
    end

    attr_reader :style

    def call(prompt:, style:)
      @style = style
      raise @error if @error

      Ai::ImageGenerator::Result.new(image: "\x89PNG fake".b, content_type: "image/png", provider: "openai",
                                     model: "gpt-image-1-mini", cost_usd: BigDecimal("0.0082"))
    end
  end

  setup do
    @user = users(:one)
    @project = @user.projects.create!(prompt: "A boxer's comeback", tone: "dramatic", target_length_minutes: 3)
    @scene = @project.scenes.create!(position: 1, text: "A small gym with a broken heater.", start_ms: 0,
                                     duration_ms: 10_000, ai_status: "generating")
    @old = @scene.images.create!(provider: "wikimedia_commons", image_url: "https://img.example/a.jpg",
                                 credit: "Jane", license: "CC0", selected: true)
    @user.grant_credits!(5, reason: "manual_grant")
    @user.charge_credits!(5, reason: "ai_image", project: @project)
  end

  def run_job(generator)
    with_stubbed_new(Ai::ImageGenerator, generator) do
      GenerateSceneImageJob.perform_now(@scene, "Old gym with a broken heater", 5)
    end
  end

  test "stores the AI image, selects it, and records its cost" do
    run_job(FakeGenerator.new)

    image = @scene.images.find_by(provider: "ai")
    assert image.file.attached?
    assert image.selected?
    assert_equal "Old gym with a broken heater", image.prompt
    assert_not @old.reload.selected?
    assert_nil @scene.reload.ai_status
    assert_equal BigDecimal("0.0082"), @project.api_usages.find_by(operation: "ai_image").cost_usd
    assert_equal true, @project.reload.settings["ai_images"]
    assert_equal 0, @user.reload.credits_balance
  end

  test "a failure refunds the credits and records the error" do
    run_job(FakeGenerator.new(error: Ai::Error.new("Image generation failed: rejected by safety system")))

    assert_equal 5, @user.reload.credits_balance
    assert_equal "ai_image_refund", @user.credit_transactions.order(:id).last.reason
    assert_equal "failed", @scene.reload.ai_status
    assert_equal "Image generation failed: rejected by safety system", @scene.ai_error
    assert @old.reload.selected?
    assert_nil @project.api_usages.find_by(operation: "ai_image")
  end

  test "a real-person scene is generated as an illustration and labelled so" do
    @scene.update!(plan: { "ai_fallback_allowed" => false })
    generator = FakeGenerator.new

    run_job(generator)

    assert_equal "illustration", generator.style
    assert_equal "AI illustration", @scene.images.find_by(provider: "ai").credit
  end
end
