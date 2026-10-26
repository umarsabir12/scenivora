module ApplicationHelper
  FIELD_CLASSES = "mt-1 block w-full rounded-lg border border-white/10 bg-[#0c0e12] px-3 py-2 text-zinc-100 placeholder:text-zinc-500 focus:border-amber-400/60 focus:outline-none focus:ring-2 focus:ring-amber-400/20".freeze
  BUTTON_CLASSES = "inline-flex items-center justify-center gap-2 rounded-lg bg-[#f0b95a] px-4 py-2 text-sm font-semibold text-zinc-950 shadow-sm hover:bg-[#f5c879] focus:outline-none focus:ring-2 focus:ring-amber-300/40 disabled:cursor-not-allowed disabled:opacity-60 cursor-pointer".freeze
  SECONDARY_BUTTON_CLASSES = "inline-flex items-center justify-center gap-2 rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm font-semibold text-zinc-200 hover:bg-white/10 focus:outline-none focus:ring-2 focus:ring-amber-300/20 disabled:cursor-not-allowed disabled:opacity-60 cursor-pointer".freeze

  def field_classes = FIELD_CLASSES
  def button_classes = BUTTON_CLASSES
  def secondary_button_classes = SECONDARY_BUTTON_CLASSES

  def flash_classes(type)
    case type.to_s
    when "alert" then "border-red-500/30 bg-red-500/10 text-red-300"
    else "border-emerald-500/30 bg-emerald-500/10 text-emerald-300"
    end
  end
end
