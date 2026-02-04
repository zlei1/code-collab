module ApplicationHelper
  AVATAR_COLORS = ["#3B82F6", "#F472B6", "#F59E0B", "#22C55E", "#8B5CF6"].freeze

  def user_display_name(user)
    return "Guest" unless user
    user.display_name.presence || user.email
  end

  def user_presence_label(user)
    return "Guest" unless user
    display = user.display_name.to_s.strip
    return user.email.to_s if display.blank?
    "#{display} - #{user.email}"
  end

  def user_initials(user)
    return "?" unless user
    source = user.display_name.presence || user.email.to_s
    letters = source.scan(/\b[A-Za-z0-9]/).first(2)
    return source.to_s[0, 2].upcase if letters.empty?
    letters.join.upcase
  end

  def avatar_color(index)
    AVATAR_COLORS[index % AVATAR_COLORS.length]
  end
end
