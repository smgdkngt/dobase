class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    in_language_of(user) { mail subject: _("Reset your password"), to: user.email_address }
  end
end
