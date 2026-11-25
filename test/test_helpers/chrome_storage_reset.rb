# frozen_string_literal: true

module ChromeStorageReset
  private

  def execute_cdp(cmd, params = {})
    return super unless cmd == "Storage.clearDataForOrigin" && params[:origin] == "*"

    super("Network.clearBrowserCookies")
    origin = Capybara.current_session.server&.base_url
    super(cmd, **params, origin: origin) if origin
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeStorageReset)
