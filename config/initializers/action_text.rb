# frozen_string_literal: true

# The editor writes h2–h6 and code blocks, but Action Text's plain-text
# conversion only treats h1 and p as blocks, so "<h2>Voice</h2><p>Fun</p>"
# became "VoiceFun" in previews and API responses.
ActiveSupport.on_load(:action_text_content) do
  ActionText::PlainTextConversion.module_eval do
    %i[ h2 h3 h4 h5 h6 pre ].each do |element|
      alias_method :"plain_text_for_#{element}_node", :plain_text_for_block
    end
  end
end
