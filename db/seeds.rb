# frozen_string_literal: true

puts "Seeding tool types..."

tool_types = [
  { name: "Todos", slug: "todos", icon: "check-square", description: "Task lists and to-do management" },
  { name: "Chat", slug: "chat", icon: "messages-square", description: "Real-time messaging and chat rooms" },
  { name: "Board", slug: "boards", icon: "layout", description: "Kanban boards for project management" },
  { name: "Files", slug: "files", icon: "folder", description: "File storage and sharing" },
  { name: "Docs", slug: "docs", icon: "file-text", description: "Collaborative documents and notes" },
  { name: "Mail", slug: "mail", icon: "mail", description: "Email client and inbox management" },
  { name: "Calendar", slug: "calendar", icon: "calendar", description: "Connect to your calendars" },
  { name: "Room", slug: "room", icon: "video", description: "Video conferencing rooms" }
]

tool_types.each do |attrs|
  ToolType.find_or_create_by!(slug: attrs[:slug]) do |tool_type|
    tool_type.name = attrs[:name]
    tool_type.icon = attrs[:icon]
    tool_type.description = attrs[:description]
    tool_type.enabled = true
  end
end

puts "Created #{ToolType.count} tool types"

# =============================================================================
# Demo seed data — run with: SEED_DEMO=1 bin/rails db:seed
# =============================================================================
if ENV["SEED_DEMO"]
  require "open-uri"

  puts "\nSeeding demo data for Moonshot Snacks..."

  # ---------------------------------------------------------------------------
  # Users
  # ---------------------------------------------------------------------------
  sophie = User.find_or_create_by!(email_address: "sophie@moonshot-snacks.com") do |u|
    u.first_name = "Sophie"
    u.last_name = "Chen"
    u.password = "password123"
  end

  marcus = User.find_or_create_by!(email_address: "marcus@moonshot-snacks.com") do |u|
    u.first_name = "Marcus"
    u.last_name = "Rivera"
    u.password = "password123"
  end

  priya = User.find_or_create_by!(email_address: "priya@moonshot-snacks.com") do |u|
    u.first_name = "Priya"
    u.last_name = "Patel"
    u.password = "password123"
  end

  jake = User.find_or_create_by!(email_address: "jake@moonshot-snacks.com") do |u|
    u.first_name = "Jake"
    u.last_name = "Thompson"
    u.password = "password123"
  end

  # Attach avatars
  { sophie => "Sophie Chen", marcus => "Marcus Rivera", priya => "Priya Patel", jake => "Jake Thompson" }.each do |user, seed_name|
    next if user.avatar.attached?

    url = "https://api.dicebear.com/9.x/notionists/png?seed=#{CGI.escape(seed_name)}&size=200"
    begin
      avatar_data = URI.parse(url).open
      user.avatar.attach(io: avatar_data, filename: "#{seed_name.parameterize}.png", content_type: "image/png")
      puts "  Attached avatar for #{user.name}"
    rescue => e
      puts "  Skipped avatar for #{user.name}: #{e.message}"
    end
  end

  puts "  Created #{User.count} users"

  # Helper to add collaborators (owner is auto-added by callback)
  def add_collaborators(tool, users)
    users.each do |user|
      next if tool.collaborators.exists?(user: user)
      tool.collaborators.create!(user: user, role: "collaborator")
    end
  end

  # ---------------------------------------------------------------------------
  # 1. Product Launch — Board (all 4 users)
  # ---------------------------------------------------------------------------
  launch_board_tool = Tool.create!(
    name: "Product Launch",
    owner: sophie,
    tool_type: ToolType.find_by!(slug: "boards")
  )
  add_collaborators(launch_board_tool, [marcus, priya, jake])

  board = launch_board_tool.board
  board.columns.destroy_all
  backlog  = board.columns.create!(name: "Backlog", position: 0)
  todo     = board.columns.create!(name: "To Do", position: 1)
  progress = board.columns.create!(name: "In Progress", position: 2)
  review   = board.columns.create!(name: "Review", position: 3)
  done     = board.columns.create!(name: "Done", position: 4)

  # Backlog cards
  backlog.cards.create!(title: "Research zero-gravity packaging regulations", position: 0, color: "blue", created_by: sophie, updated_by: sophie)
  backlog.cards.create!(title: "Plan influencer outreach for astronaut community", position: 1, created_by: marcus, updated_by: marcus)
  backlog.cards.create!(title: "Set up analytics dashboard", position: 2, color: "purple", assigned_user: jake, created_by: sophie, updated_by: sophie)

  # To Do cards
  c1 = todo.cards.create!(title: "Write press release for launch day", position: 0, color: "yellow", assigned_user: marcus, due_date: 5.days.from_now, created_by: sophie, updated_by: sophie)
  c1.update!(description: "<p>We need a punchy press release. Key points:</p><ul><li>World's first snack designed for space tourists</li><li>Quote from our taste tester at SpaceX</li><li>Mention the Kickstarter stretch goals</li></ul>")

  todo.cards.create!(title: "Order sample packaging from printer", position: 1, assigned_user: priya, due_date: 3.days.from_now, created_by: priya, updated_by: priya)

  # In Progress cards
  c2 = progress.cards.create!(title: "Design landing page", position: 0, color: "green", assigned_user: priya, due_date: 2.days.from_now, created_by: sophie, updated_by: sophie)
  c2.update!(description: "<p>Hero section with floating snacks in zero-g. Make it feel <strong>weightless</strong>.</p>")

  Boards::Comment.create!(card: c2, user: marcus, body: "<p>Love the zero-g concept! Can we add a countdown timer to launch day?</p>")
  Boards::Comment.create!(card: c2, user: priya, body: "<p>Already on it! Also adding parallax scrolling so the crumbs float as you scroll.</p>")

  c3 = progress.cards.create!(title: "Finalize flavor lineup for v1", position: 1, color: "orange", assigned_user: marcus, created_by: marcus, updated_by: marcus)
  c3.update!(description: "<p>Current candidates:</p><ol><li>Cosmic Crunch (honey sesame)</li><li>Nebula Bites (dark chocolate chili)</li><li>Orbit Rings (everything bagel)</li></ol><p>Need to drop one due to budget. I vote we keep all three and skip lunch for a month.</p>")

  progress.cards.create!(title: "Build online store backend", position: 2, color: "purple", assigned_user: jake, created_by: jake, updated_by: jake)

  # Review cards
  c4 = review.cards.create!(title: "Logo and brand identity package", position: 0, color: "green", assigned_user: priya, created_by: priya, updated_by: priya)
  Boards::Comment.create!(card: c4, user: sophie, body: "<p>The rocket-shaped pretzel logo is perfect. Ship it!</p>")

  review.cards.create!(title: "Nutritional labels draft", position: 1, assigned_user: marcus, created_by: marcus, updated_by: marcus)

  # Done cards
  done.cards.create!(title: "Register business and trademark", position: 0, color: "blue", assigned_user: sophie, created_by: sophie, updated_by: sophie)
  done.cards.create!(title: "Find commercial kitchen space", position: 1, assigned_user: sophie, created_by: sophie, updated_by: sophie)

  puts "  Created Product Launch board with #{board.cards.count} cards"

  # ---------------------------------------------------------------------------
  # 2. Team Chat (all 4 users)
  # ---------------------------------------------------------------------------
  chat_tool = Tool.create!(
    name: "Team Chat",
    owner: sophie,
    tool_type: ToolType.find_by!(slug: "chat")
  )
  add_collaborators(chat_tool, [marcus, priya, jake])

  chat = chat_tool.chat
  base_time = 2.hours.ago

  messages = [
    [sophie, "Good morning team! Big day — we got our first wholesale inquiry from a space tourism company"],
    [marcus, "Wait WHAT?! Which one??"],
    [sophie, "Galactic Adventures. They want to stock our snacks on their suborbital flights!"],
    [priya, "That's amazing!! Do they know we haven't actually launched yet? Asking for a friend"],
    [sophie, "They saw our Instagram teaser. Apparently their CEO is a sucker for everything bagel flavor"],
    [jake, "Their website is built on WordPress though. Should I be worried about the partnership?"],
    [marcus, "Jake, not everything is about the tech stack"],
    [jake, "I'm just saying, if they can't handle a website, can they handle orbit?"],
    [priya, "I just finished the packaging mockups by the way. Sending to the printer today"],
    [sophie, "Can you share them in Team Files? I want Marcus to review before we print"],
    [marcus, "Already reviewed! The 'Cosmic Crunch' bag looks incredible. Only note: can we make the astronaut on the back look less terrified?"],
    [priya, "That's not terror, that's the face you make when you eat really good snacks in zero gravity"],
    [jake, "I deployed the store to staging btw. Everything works except the checkout — turns out Stripe doesn't have a 'pay in space credits' option"],
    [sophie, "Regular Earth money is fine for now, Jake"],
    [marcus, "Team standup at 2pm? I want to sync on the launch timeline. We're T-minus 3 weeks!"],
  ]

  messages.each_with_index do |(user, body), i|
    chat.messages.create!(user: user, body: "<p>#{body}</p>", created_at: base_time + (i * 3).minutes)
  end

  puts "  Created Team Chat with #{chat.messages.count} messages"

  # ---------------------------------------------------------------------------
  # 3. Launch Tasks — Todos (Sophie, Marcus, Priya)
  # ---------------------------------------------------------------------------
  tasks_tool = Tool.create!(
    name: "Launch Tasks",
    owner: sophie,
    tool_type: ToolType.find_by!(slug: "todos")
  )
  add_collaborators(tasks_tool, [marcus, priya])

  # Rename the auto-created default list
  pre_launch = tasks_tool.todo_lists.first
  pre_launch.update!(title: "Pre-Launch Checklist", created_by: sophie, updated_by: sophie)

  post_launch = tasks_tool.todo_lists.create!(title: "Post-Launch", position: 1, created_by: sophie, updated_by: sophie)

  # Pre-launch items
  pre_launch.items.create!(title: "Finalize pricing for all SKUs", position: 0, assigned_user: marcus, completed_at: 3.days.ago, created_by: sophie, updated_by: marcus)
  pre_launch.items.create!(title: "Set up Stripe account and test payments", position: 1, assigned_user: jake, completed_at: 2.days.ago, created_by: sophie, updated_by: jake)
  pre_launch.items.create!(title: "Submit FDA compliance paperwork", position: 2, assigned_user: sophie, completed_at: 1.day.ago, created_by: sophie, updated_by: sophie)
  pre_launch.items.create!(title: "Print first batch of packaging (500 units)", position: 3, assigned_user: priya, due_date: 4.days.from_now, created_by: priya, updated_by: priya)
  i1 = pre_launch.items.create!(title: "Write launch email newsletter", position: 4, assigned_user: marcus, due_date: 6.days.from_now, created_by: marcus, updated_by: marcus)
  i1.update!(description: "<p>Subject line ideas:</p><ul><li>'Houston, we have snacks'</li><li>'One small bite for man...'</li><li>'Snacks that are out of this world (literally)'</li></ul>")
  pre_launch.items.create!(title: "Schedule social media posts for launch week", position: 5, assigned_user: priya, due_date: 7.days.from_now, created_by: sophie, updated_by: sophie)
  pre_launch.items.create!(title: "Coordinate with food bloggers for reviews", position: 6, assigned_user: marcus, created_by: marcus, updated_by: marcus)

  # Post-launch items
  post_launch.items.create!(title: "Send thank-you notes to early supporters", position: 0, assigned_user: sophie, created_by: sophie, updated_by: sophie)
  post_launch.items.create!(title: "Collect and respond to first customer reviews", position: 1, assigned_user: marcus, created_by: marcus, updated_by: marcus)
  post_launch.items.create!(title: "Analyze first week sales data", position: 2, assigned_user: sophie, created_by: sophie, updated_by: sophie)

  puts "  Created Launch Tasks with #{Todos::Item.count} items"

  # ---------------------------------------------------------------------------
  # 4. Launch Docs (Sophie, Marcus, Priya)
  # ---------------------------------------------------------------------------
  docs_tool = Tool.create!(
    name: "Launch Docs",
    owner: sophie,
    tool_type: ToolType.find_by!(slug: "docs")
  )
  add_collaborators(docs_tool, [marcus, priya])

  doc1 = docs_tool.documents.create!(title: "Brand Guidelines", created_by: sophie, updated_by: priya, last_edited_at: 1.day.ago)
  doc1.update!(content: <<~HTML)
    <h1>Moonshot Snacks — Brand Guidelines</h1>
    <h2>Mission Statement</h2>
    <p>To make snacks so good they're worth the trip to space. And also good on Earth. Mostly on Earth, for now.</p>
    <h2>Brand Voice</h2>
    <p>Fun, adventurous, slightly nerdy. We're the friend who brings the best snacks to game night AND knows all the constellations.</p>
    <ul>
      <li><strong>Do:</strong> Use space puns. Customers love them. We tested this.</li>
      <li><strong>Do:</strong> Be enthusiastic about ingredients. We genuinely care about this stuff.</li>
      <li><strong>Don't:</strong> Be condescending about other snacks. All snacks are valid.</li>
      <li><strong>Don't:</strong> Use the phrase "rocket fuel" — legal said no.</li>
    </ul>
    <h2>Colors</h2>
    <p>Primary: Deep Space Navy (#1a1a3e), Cosmic Orange (#ff6b35)</p>
    <p>Secondary: Stardust Silver (#c0c0c0), Nebula Purple (#6b35ff)</p>
  HTML

  doc2 = docs_tool.documents.create!(title: "Launch Day Runbook", created_by: marcus, updated_by: marcus, last_edited_at: 6.hours.ago)
  doc2.update!(content: <<~HTML)
    <h1>Launch Day Runbook</h1>
    <h2>Timeline (All times EST)</h2>
    <p><strong>6:00 AM</strong> — Sophie sends launch email to mailing list (3,247 subscribers)</p>
    <p><strong>7:00 AM</strong> — Instagram/Twitter/TikTok posts go live (Priya)</p>
    <p><strong>8:00 AM</strong> — Website goes live with store (Jake)</p>
    <p><strong>9:00 AM</strong> — Reddit AMA in r/snacks and r/space (Marcus)</p>
    <p><strong>12:00 PM</strong> — Check-in call. Cry tears of joy or regular tears.</p>
    <p><strong>5:00 PM</strong> — End of day recap. Order celebratory pizza (ironic, we know).</p>
    <h2>Emergency Contacts</h2>
    <p>If the website goes down: Jake (he sleeps with his laptop, it's fine)</p>
    <p>If we go viral: Everyone panic calmly</p>
  HTML

  doc3 = docs_tool.documents.create!(title: "FAQ Draft", created_by: marcus, updated_by: sophie, last_edited_at: 2.days.ago)
  doc3.update!(content: <<~HTML)
    <h1>Frequently Asked Questions</h1>
    <p><strong>Q: Can I actually eat these in space?</strong></p>
    <p>A: Technically yes! Our snacks are crumb-free by design, which is a real requirement for space food. We haven't been to space yet, but we've tested them upside down.</p>
    <p><strong>Q: Are they vegan?</strong></p>
    <p>A: Cosmic Crunch and Orbit Rings are vegan. Nebula Bites contain dark chocolate with milk powder. We're working on a vegan version — codename: Dark Matter Bites.</p>
    <p><strong>Q: Do you ship internationally?</strong></p>
    <p>A: We ship to all countries on Earth. Other planets: coming soon.</p>
    <p><strong>Q: Why are they called "Moonshot Snacks"?</strong></p>
    <p>A: Because "Adequate Snacks That Are Slightly Better Than Average" didn't fit on the packaging.</p>
  HTML

  puts "  Created Launch Docs with #{docs_tool.documents.count} documents"

  # ---------------------------------------------------------------------------
  # 5. Team Files (all 4 users)
  # ---------------------------------------------------------------------------
  files_tool = Tool.create!(
    name: "Team Files",
    owner: sophie,
    tool_type: ToolType.find_by!(slug: "files")
  )
  add_collaborators(files_tool, [marcus, priya, jake])

  brand_folder = files_tool.file_folders.create!(name: "Brand Assets", position: 0, created_by: priya, updated_by: priya)
  recipes_folder = files_tool.file_folders.create!(name: "Recipes", position: 1, created_by: sophie, updated_by: sophie)
  legal_folder = files_tool.file_folders.create!(name: "Legal Documents", position: 2, created_by: sophie, updated_by: sophie)

  # Helper to create a file item with an in-memory attachment
  def create_text_file(tool, folder:, name:, content:, content_type: "text/plain", created_by:, position: 0)
    item = tool.file_items.create!(name: name, folder: folder, position: position, created_by: created_by, updated_by: created_by)
    item.file.attach(io: StringIO.new(content), filename: name, content_type: content_type)
    item.save! # trigger cache_file_metadata
    item
  end

  # Generate a minimal valid PNG with a solid color (no dependencies needed)
  def create_png_data(r, g, b, width: 100, height: 100)
    require "zlib"
    raw_data = (0...height).map { "\x00" + ([r, g, b].pack("C3") * width) }.join
    compressed = Zlib::Deflate.deflate(raw_data)

    png = "\x89PNG\r\n\x1A\n".b
    # IHDR chunk
    ihdr_data = [width, height, 8, 2, 0, 0, 0].pack("NNCCCCC")
    png << [13].pack("N") << "IHDR" << ihdr_data << [Zlib.crc32("IHDR" + ihdr_data)].pack("N")
    # IDAT chunk
    png << [compressed.bytesize].pack("N") << "IDAT" << compressed << [Zlib.crc32("IDAT" + compressed)].pack("N")
    # IEND chunk
    png << [0].pack("N") << "IEND" << [Zlib.crc32("IEND")].pack("N")
    png
  end

  def create_image_file(tool, folder:, name:, png_data:, created_by:, position: 0)
    item = tool.file_items.create!(name: name, folder: folder, position: position, created_by: created_by, updated_by: created_by)
    item.file.attach(io: StringIO.new(png_data), filename: name, content_type: "image/png")
    item.save!
    item
  end

  # Brand Assets — solid color PNGs as design placeholders
  create_image_file(files_tool, folder: brand_folder, name: "moonshot-logo.png", position: 0, created_by: priya,
    png_data: create_png_data(26, 26, 62, width: 200, height: 200))  # Deep Space Navy

  create_text_file(files_tool, folder: brand_folder, name: "color-palette.txt", position: 1, created_by: priya, content: <<~TXT)
    Moonshot Snacks — Color Palette
    ================================

    Primary Colors:
      Deep Space Navy    #1a1a3e   RGB(26, 26, 62)
      Cosmic Orange      #ff6b35   RGB(255, 107, 53)

    Secondary Colors:
      Stardust Silver    #c0c0c0   RGB(192, 192, 192)
      Nebula Purple      #6b35ff   RGB(107, 53, 255)

    Accent Colors:
      Meteor Red         #e63946   RGB(230, 57, 70)
      Galaxy Teal        #2ec4b6   RGB(46, 196, 182)

    Usage Notes:
      - Deep Space Navy for backgrounds and headers
      - Cosmic Orange for CTAs and highlights
      - Never use orange on navy at small sizes (contrast!)
  TXT

  create_text_file(files_tool, folder: brand_folder, name: "social-media-bio.txt", position: 2, created_by: marcus, content: <<~TXT)
    Instagram Bio:
    Snacks engineered for space. Enjoyed on Earth. 🚀
    Crumb-free by design. Flavor-full by obsession.
    Pre-order now ↓ moonshot-snacks.com

    Twitter/X Bio:
    Making artisanal snacks for astronauts (and everyone else).
    Founders: @sophiechen @marcusrivera
    🚀 Launching soon

    TikTok Bio:
    snacks so good they're literally rocket fuel*
    *legal made us remove this claim
  TXT

  create_image_file(files_tool, folder: brand_folder, name: "cosmic-crunch-label.png", position: 3, created_by: priya,
    png_data: create_png_data(255, 107, 53, width: 300, height: 150))  # Cosmic Orange

  # Recipes folder
  create_text_file(files_tool, folder: recipes_folder, name: "cosmic-crunch-v3.txt", position: 0, created_by: sophie, content: <<~TXT)
    COSMIC CRUNCH v3 — Final Recipe
    ================================

    Yield: ~50 bags (2.5 oz each)

    Ingredients:
      - 4 lbs sesame seeds (white, unhulled)
      - 2 lbs raw honey (local wildflower)
      - 1 lb brown rice syrup
      - 0.5 lb coconut oil
      - 2 tbsp sea salt flakes (Maldon)
      - 1 tbsp vanilla extract

    Process:
      1. Toast sesame seeds at 325°F for 12-14 min (watch carefully!)
      2. Heat honey + rice syrup to 280°F (soft crack stage)
      3. Fold in toasted seeds, coconut oil, vanilla
      4. Press into sheet pan, score into bars
      5. Cool completely (2 hours minimum)
      6. Break along score lines, package immediately

    Notes:
      - v3 reduced honey by 10% from v2 — less sticky, better snap
      - Added sea salt flakes on top — game changer
      - Shelf stable for 6+ months in sealed packaging
  TXT

  create_text_file(files_tool, folder: recipes_folder, name: "nebula-bites-v2.txt", position: 1, created_by: sophie, content: <<~TXT)
    NEBULA BITES v2 — Recipe
    =========================

    Yield: ~60 bags (2 oz each)

    Ingredients:
      - 3 lbs dark chocolate (72% cacao, Valrhona)
      - 1.5 lbs roasted almonds, roughly chopped
      - 4 tbsp dried chili flakes (Korean gochugaru)
      - 2 tbsp cocoa powder
      - 1 tbsp smoked paprika
      - 1 tsp cayenne (optional — Marcus says yes, Sophie says no)

    Process:
      1. Temper chocolate to 88°F
      2. Fold in almonds and spice blend
      3. Pipe into silicone sphere molds (1 inch diameter)
      4. Tap molds to remove bubbles
      5. Chill at 60°F for 45 minutes
      6. Unmold, dust with cocoa powder

    Notes:
      - The chili heat hits about 3 seconds after the chocolate
      - Customers describe it as "a hug followed by a surprise"
      - Vegan version in development (coconut milk powder swap)
  TXT

  create_text_file(files_tool, folder: recipes_folder, name: "orbit-rings-v1.txt", position: 2, created_by: marcus, content: <<~TXT)
    ORBIT RINGS v1 — Recipe
    ========================

    Yield: ~45 bags (3 oz each)

    Ingredients:
      - 3 lbs pretzel dough (standard recipe)
      - 1 cup everything bagel seasoning blend:
          - Sesame seeds, poppy seeds, dried garlic,
            dried onion, sea salt (equal parts)
      - 0.5 cup butter (for brushing)
      - 2 tbsp honey (for glaze)

    Process:
      1. Roll dough into thin ropes, form into 2-inch rings
      2. Boil in baking soda water (30 seconds each)
      3. Brush with butter-honey glaze
      4. Coat generously in everything seasoning
      5. Bake at 425°F for 10-12 minutes
      6. Cool on wire rack, package when room temp

    Notes:
      - Ring shape = no crumbs in zero gravity
      - The honey glaze makes the seasoning stick perfectly
      - These are dangerously addictive. Hide them from Jake.
  TXT

  # Legal Documents folder
  create_text_file(files_tool, folder: legal_folder, name: "fda-submission-receipt.txt", position: 0, created_by: sophie, content: <<~TXT)
    FDA Food Product Compliance Submission
    =======================================
    Reference: FD-2026-4821
    Date: March 1, 2026
    Status: Under Review

    Products Submitted:
      1. Cosmic Crunch (Honey Sesame Bar)
      2. Nebula Bites (Dark Chocolate Chili Spheres)
      3. Orbit Rings (Everything Seasoned Pretzel Rings)

    Expected Review Timeline: 15 business days
    Contact: compliance@fda.gov
  TXT

  create_text_file(files_tool, folder: legal_folder, name: "trademark-registration.txt", position: 1, created_by: sophie, content: <<~TXT)
    Trademark Registration — Moonshot Snacks LLC
    ==============================================
    Registration Number: TM-2026-889412
    Filing Date: January 15, 2026
    Status: Registered

    Marks:
      - "Moonshot Snacks" (word mark)
      - "Cosmic Crunch" (word mark)
      - "Nebula Bites" (word mark)
      - "Orbit Rings" (word mark)
      - Moonshot Snacks logo (design mark)

    Classes: 029 (Processed foods), 030 (Snack foods)
  TXT

  create_text_file(files_tool, folder: legal_folder, name: "cloudkitchens-lease.txt", position: 2, created_by: sophie, content: <<~TXT)
    Commercial Kitchen Lease Agreement — Summary
    ==============================================
    Tenant: Moonshot Snacks LLC
    Landlord: CloudKitchens Inc.
    Location: Unit 12, 500 Industrial Blvd, Austin TX

    Term: 12 months (Jan 1 — Dec 31, 2026)
    Monthly Rent: $2,400
    Includes: Commercial oven, prep stations, cold storage,
              packaging area, shared loading dock

    Insurance: Tenant must maintain $1M liability coverage
    Hours: 24/7 access with keycard
  TXT

  # Root-level files (no folder)
  create_text_file(files_tool, folder: nil, name: "launch-checklist.csv", position: 0, created_by: sophie, content_type: "text/csv", content: <<~CSV)
    Task,Owner,Due Date,Status
    Finalize pricing,Marcus,2026-03-08,Done
    Set up Stripe,Jake,2026-03-09,Done
    FDA submission,Sophie,2026-03-10,Done
    Print packaging (500 units),Priya,2026-03-15,In Progress
    Launch email newsletter,Marcus,2026-03-17,Not Started
    Social media schedule,Priya,2026-03-18,Not Started
    Coordinate food bloggers,Marcus,2026-03-20,Not Started
    Launch day!!,Everyone,2026-04-01,Not Started
  CSV

  create_text_file(files_tool, folder: nil, name: "team-contacts.txt", position: 1, created_by: sophie, content: <<~TXT)
    Moonshot Snacks — Team Contacts
    ================================

    Sophie Chen (CEO)         sophie@moonshot-snacks.com
    Marcus Rivera (Product)   marcus@moonshot-snacks.com
    Priya Patel (Design)      priya@moonshot-snacks.com
    Jake Thompson (Eng)       jake@moonshot-snacks.com

    Key Partners:
    PrintCo Express           orders@printco-express.com
    CloudKitchens             support@cloudkitchens.co
    Bulk Foods Supply         sales@bulkfoods-supply.com
  TXT

  puts "  Created Team Files with #{files_tool.file_folders.count} folders and #{files_tool.file_items.count} files"

  # ---------------------------------------------------------------------------
  # 6. Standup Room (all 4 users)
  # ---------------------------------------------------------------------------
  room_tool = Tool.create!(
    name: "Standup Room",
    owner: sophie,
    tool_type: ToolType.find_by!(slug: "room")
  )
  add_collaborators(room_tool, [marcus, priya, jake])

  puts "  Created Standup Room"

  # ---------------------------------------------------------------------------
  # 7. Snack Ideas — Board (Sophie & Marcus)
  # ---------------------------------------------------------------------------
  ideas_tool = Tool.create!(
    name: "Snack Ideas",
    owner: sophie,
    tool_type: ToolType.find_by!(slug: "boards")
  )
  add_collaborators(ideas_tool, [marcus])

  ideas_board = ideas_tool.board
  ideas_board.columns.destroy_all
  ideas_col    = ideas_board.columns.create!(name: "Ideas", position: 0)
  research_col = ideas_board.columns.create!(name: "Researching", position: 1)
  testing_col  = ideas_board.columns.create!(name: "Testing", position: 2)
  approved_col = ideas_board.columns.create!(name: "Approved", position: 3)

  ideas_col.cards.create!(title: "Freeze-dried ramen bites", position: 0, color: "yellow", created_by: marcus, updated_by: marcus)
  ideas_col.cards.create!(title: "Matcha white chocolate clusters", position: 1, color: "green", created_by: sophie, updated_by: sophie)
  ideas_col.cards.create!(title: "Spicy mango jerky strips", position: 2, color: "red", created_by: marcus, updated_by: marcus)

  research_col.cards.create!(title: "Protein-packed cheese puffs", position: 0, color: "orange", created_by: marcus, updated_by: marcus)
  rc = research_col.cards.create!(title: "Edible cookie dough spheres", position: 1, color: "purple", created_by: sophie, updated_by: sophie)
  rc.update!(description: "<p>Perfectly round so they float beautifully in zero-g. Marketing writes itself.</p>")

  testing_col.cards.create!(title: "Wasabi pea crunch mix", position: 0, color: "green", created_by: marcus, updated_by: marcus)

  approved_col.cards.create!(title: "Cosmic Crunch (honey sesame)", position: 0, color: "yellow", created_by: sophie, updated_by: sophie)
  approved_col.cards.create!(title: "Nebula Bites (dark chocolate chili)", position: 1, color: "red", created_by: marcus, updated_by: marcus)

  puts "  Created Snack Ideas board with #{ideas_board.cards.count} cards"

  # ---------------------------------------------------------------------------
  # 8. Sophie's Mail
  # ---------------------------------------------------------------------------
  mail_tool = Tool.create!(
    name: "Mail",
    owner: sophie,
    tool_type: ToolType.find_by!(slug: "mail")
  )

  mail_account = Mails::Account.create!(
    tool: mail_tool,
    email_address: "sophie@moonshot-snacks.com",
    imap_host: "imap.moonshot-snacks.com",
    smtp_host: "smtp.moonshot-snacks.com",
    username: "sophie@moonshot-snacks.com",
    password: "demo-password",
    smtp_auth: "plain",
    sync_status: "synced",
    synced_folders: '["INBOX","Sent"]'
  )

  important_label = mail_account.labels.create!(name: "Important", color: "#ef4444")
  investors_label = mail_account.labels.create!(name: "Investors", color: "#8b5cf6")

  # Inbox emails
  m1 = mail_account.messages.create!(
    message_id: "<001@moonshot-snacks.com>",
    uid: 1,
    folder: "INBOX",
    subject: "Partnership Inquiry — Galactic Adventures",
    from_name: "Tom Bradley",
    from_address: "tom@galacticadventures.com",
    to_addresses: '["sophie@moonshot-snacks.com"]',
    body_html: "<p>Hi Sophie,</p><p>I'm the CEO of Galactic Adventures. We're launching suborbital tourist flights next year and we're looking for premium snack partners. Your Instagram caught my eye — especially the everything bagel flavor.</p><p>Would love to chat about stocking Moonshot Snacks on our flights. Our passengers deserve better than freeze-dried ice cream!</p><p>Best,<br>Tom</p>",
    body_plain: "Hi Sophie, I'm the CEO of Galactic Adventures. We're launching suborbital tourist flights next year and we're looking for premium snack partners. Your Instagram caught my eye — especially the everything bagel flavor. Would love to chat about stocking Moonshot Snacks on our flights. Our passengers deserve better than freeze-dried ice cream! Best, Tom",
    sent_at: 1.day.ago,
    read: false,
    starred: true
  )
  m1.label_assignments.create!(label: important_label)

  mail_account.messages.create!(
    message_id: "<002@moonshot-snacks.com>",
    uid: 2,
    folder: "INBOX",
    subject: "Your FDA Submission Has Been Received",
    from_name: "FDA Notifications",
    from_address: "noreply@fda.gov",
    to_addresses: '["sophie@moonshot-snacks.com"]',
    body_html: "<p>Dear Sophie Chen,</p><p>This email confirms receipt of your food product compliance submission #FD-2026-4821. Expected review time: 15 business days.</p><p>Thank you,<br>U.S. Food & Drug Administration</p>",
    body_plain: "Dear Sophie Chen, This email confirms receipt of your food product compliance submission #FD-2026-4821. Expected review time: 15 business days.",
    sent_at: 2.days.ago,
    read: true,
    starred: false
  )

  mail_account.messages.create!(
    message_id: "<003@moonshot-snacks.com>",
    uid: 3,
    folder: "INBOX",
    subject: "Re: Packaging samples ready for pickup",
    from_name: "PrintCo Express",
    from_address: "orders@printco-express.com",
    to_addresses: '["sophie@moonshot-snacks.com"]',
    body_html: "<p>Hi Sophie,</p><p>Your packaging sample order (#PCE-7291) is ready for pickup at our downtown location. The metallic finish on the Cosmic Crunch bags turned out great!</p><p>Open until 6pm today.</p><p>Thanks,<br>PrintCo Team</p>",
    body_plain: "Hi Sophie, Your packaging sample order (#PCE-7291) is ready for pickup at our downtown location. The metallic finish on the Cosmic Crunch bags turned out great! Open until 6pm today.",
    sent_at: 3.hours.ago,
    read: false,
    starred: false
  )

  m4 = mail_account.messages.create!(
    message_id: "<004@moonshot-snacks.com>",
    uid: 4,
    folder: "INBOX",
    subject: "Seed Round Follow-up",
    from_name: "Rachel Kim",
    from_address: "rachel@northstarvc.com",
    to_addresses: '["sophie@moonshot-snacks.com"]',
    body_html: "<p>Sophie,</p><p>Thanks for the pitch yesterday. The team loved the product samples (the Nebula Bites were gone in 5 minutes). We'd like to schedule a follow-up to discuss terms.</p><p>Are you free Thursday afternoon?</p><p>Rachel Kim<br>Partner, North Star Ventures</p>",
    body_plain: "Sophie, Thanks for the pitch yesterday. The team loved the product samples (the Nebula Bites were gone in 5 minutes). We'd like to schedule a follow-up to discuss terms. Are you free Thursday afternoon? Rachel Kim, Partner, North Star Ventures",
    sent_at: 5.hours.ago,
    read: false,
    starred: true
  )
  m4.label_assignments.create!(label: investors_label)
  m4.label_assignments.create!(label: important_label)

  mail_account.messages.create!(
    message_id: "<005@moonshot-snacks.com>",
    uid: 5,
    folder: "INBOX",
    subject: "Kitchen rental invoice — March 2026",
    from_name: "CloudKitchens Billing",
    from_address: "billing@cloudkitchens.co",
    to_addresses: '["sophie@moonshot-snacks.com"]',
    body_html: "<p>Hi Sophie,</p><p>Your invoice for March 2026 kitchen rental is attached. Amount due: $2,400.00. Due by March 25th.</p><p>Thanks for choosing CloudKitchens!</p>",
    body_plain: "Hi Sophie, Your invoice for March 2026 kitchen rental is attached. Amount due: $2,400.00. Due by March 25th.",
    sent_at: 1.day.ago,
    read: true,
    starred: false
  )

  # Sent emails
  mail_account.messages.create!(
    message_id: "<006@moonshot-snacks.com>",
    uid: 6,
    folder: "Sent",
    subject: "Re: Partnership Inquiry — Galactic Adventures",
    from_name: "Sophie Chen",
    from_address: "sophie@moonshot-snacks.com",
    to_addresses: '["tom@galacticadventures.com"]',
    in_reply_to: "<001@moonshot-snacks.com>",
    body_html: "<p>Hi Tom!</p><p>This is incredibly exciting — Galactic Adventures is exactly the kind of partner we've been dreaming about. I'd love to set up a call this week to discuss how we can make this happen.</p><p>Fair warning: once your passengers try our Orbit Rings, they might refuse to come back to Earth.</p><p>Best,<br>Sophie</p>",
    body_plain: "Hi Tom! This is incredibly exciting — Galactic Adventures is exactly the kind of partner we've been dreaming about. I'd love to set up a call this week to discuss how we can make this happen. Fair warning: once your passengers try our Orbit Rings, they might refuse to come back to Earth.",
    sent_at: 12.hours.ago,
    read: true,
    starred: false
  )

  mail_account.messages.create!(
    message_id: "<007@moonshot-snacks.com>",
    uid: 7,
    folder: "Sent",
    subject: "Re: Seed Round Follow-up",
    from_name: "Sophie Chen",
    from_address: "sophie@moonshot-snacks.com",
    to_addresses: '["rachel@northstarvc.com"]',
    in_reply_to: "<004@moonshot-snacks.com>",
    body_html: "<p>Hi Rachel,</p><p>So glad the team enjoyed the samples! Thursday 2pm works perfectly for me. I'll send a calendar invite.</p><p>Looking forward to it!<br>Sophie</p>",
    body_plain: "Hi Rachel, So glad the team enjoyed the samples! Thursday 2pm works perfectly for me. I'll send a calendar invite. Looking forward to it! Sophie",
    sent_at: 4.hours.ago,
    read: true,
    starred: false
  )

  mail_account.messages.create!(
    message_id: "<008@moonshot-snacks.com>",
    uid: 8,
    folder: "Sent",
    subject: "Ingredient order for next production run",
    from_name: "Sophie Chen",
    from_address: "sophie@moonshot-snacks.com",
    to_addresses: '["sales@bulkfoods-supply.com"]',
    body_html: "<p>Hi there,</p><p>I'd like to place an order for our next production batch:</p><ul><li>50 lbs organic sesame seeds</li><li>30 lbs raw honey</li><li>25 lbs dark chocolate (72% cacao)</li><li>20 lbs dried chili flakes</li></ul><p>Can you confirm availability and delivery timeline?</p><p>Thanks,<br>Sophie Chen<br>Moonshot Snacks</p>",
    body_plain: "Hi there, I'd like to place an order for our next production batch: 50 lbs organic sesame seeds, 30 lbs raw honey, 25 lbs dark chocolate (72% cacao), 20 lbs dried chili flakes. Can you confirm availability and delivery timeline?",
    sent_at: 2.days.ago,
    read: true,
    starred: false
  )

  puts "  Created Mail with #{mail_account.messages.count} emails and #{mail_account.labels.count} labels"

  # ---------------------------------------------------------------------------
  # 9. Design Calendar (Sophie only, local provider)
  # ---------------------------------------------------------------------------
  calendar_tool = Tool.create!(
    name: "Calendar",
    owner: sophie,
    tool_type: ToolType.find_by!(slug: "calendar")
  )

  cal_account = Calendars::Account.create!(
    tool: calendar_tool,
    provider: "local",
    username: "local",
    password: "local",
    sync_status: "synced"
  )

  cal = cal_account.calendars.create!(
    name: "Moonshot Calendar",
    remote_id: "local-moonshot",
    color: "#ff6b35",
    enabled: true,
    is_default: true,
    position: 0
  )

  cal.events.create!(
    summary: "Investor Follow-up Call — North Star Ventures",
    starts_at: 3.days.from_now.change(hour: 14),
    ends_at: 3.days.from_now.change(hour: 15),
    uid: SecureRandom.uuid,
    location: "Zoom",
    description: "Follow-up meeting with Rachel Kim to discuss seed round terms",
    created_by: sophie,
    updated_by: sophie
  )

  cal.events.create!(
    summary: "Production Run #4 — CloudKitchens",
    starts_at: 5.days.from_now.change(hour: 8),
    ends_at: 5.days.from_now.change(hour: 16),
    uid: SecureRandom.uuid,
    location: "CloudKitchens Downtown, Unit 12",
    description: "Full day production. Making 500 units of Cosmic Crunch and 300 units of Nebula Bites.",
    created_by: sophie,
    updated_by: sophie
  )

  cal.events.create!(
    summary: "Team Standup",
    starts_at: 1.day.from_now.change(hour: 10),
    ends_at: 1.day.from_now.change(hour: 10, min: 30),
    uid: SecureRandom.uuid,
    is_recurring: true,
    rrule: "FREQ=WEEKLY;BYDAY=MO,WE,FR",
    created_by: sophie,
    updated_by: sophie
  )

  cal.events.create!(
    summary: "Packaging Pickup — PrintCo",
    starts_at: 1.day.from_now.change(hour: 15),
    ends_at: 1.day.from_now.change(hour: 16),
    uid: SecureRandom.uuid,
    location: "PrintCo Express, 742 Evergreen Terrace",
    created_by: sophie,
    updated_by: sophie
  )

  cal.events.create!(
    summary: "Launch Day!!",
    starts_at: 21.days.from_now.beginning_of_day,
    ends_at: 21.days.from_now.end_of_day,
    uid: SecureRandom.uuid,
    all_day: true,
    description: "The big day! See Launch Day Runbook in docs.",
    created_by: sophie,
    updated_by: sophie
  )

  puts "  Created Calendar with #{cal.events.count} events"

  # ---------------------------------------------------------------------------
  # 10. Personal Notes — Docs (Sophie only)
  # ---------------------------------------------------------------------------
  notes_tool = Tool.create!(
    name: "Personal Notes",
    owner: sophie,
    tool_type: ToolType.find_by!(slug: "docs")
  )

  n1 = notes_tool.documents.create!(title: "Investor Pitch Notes", created_by: sophie, updated_by: sophie, last_edited_at: 2.days.ago)
  n1.update!(content: <<~HTML)
    <h1>Investor Pitch Notes</h1>
    <h2>Key Numbers</h2>
    <ul>
      <li>TAM: $3.2B space tourism food market by 2030</li>
      <li>Pre-orders: 847 units across 3 SKUs</li>
      <li>Instagram followers: 12.4K (grew 3x in 2 months)</li>
      <li>Unit cost: $2.10, retail price: $7.99 (74% margin)</li>
      <li>Commercial kitchen overhead: $2,400/month</li>
    </ul>
    <h2>Questions to Expect</h2>
    <ul>
      <li>How do we scale production? → CloudKitchens can 5x our capacity</li>
      <li>Competition? → No one else targeting space tourism + premium snacks</li>
      <li>Why not just sell on Amazon? → We will, but DTC first for brand building</li>
    </ul>
    <h2>Personal Reminders</h2>
    <p>Don't forget to bring samples. Last time Marcus ate them all in the car.</p>
  HTML

  n2 = notes_tool.documents.create!(title: "Meeting Notes — March 7", created_by: sophie, updated_by: sophie, last_edited_at: 4.days.ago)
  n2.update!(content: <<~HTML)
    <h1>Meeting Notes — March 7</h1>
    <h2>Attendees</h2>
    <p>Sophie, Marcus, Priya, Jake</p>
    <h2>Discussion</h2>
    <ul>
      <li>Priya showed new packaging — everyone loves the metallic finish</li>
      <li>Jake's store is 90% done, just needs payment integration</li>
      <li>Marcus wants to do a Reddit AMA on launch day — approved</li>
      <li>Decided to push launch back 1 week to get packaging right</li>
    </ul>
    <h2>Action Items</h2>
    <ul>
      <li>Sophie: Confirm new launch date with printer</li>
      <li>Jake: Finish Stripe integration by Friday</li>
      <li>Marcus: Draft AMA talking points</li>
      <li>Priya: Final packaging proof review</li>
    </ul>
  HTML

  puts "  Created Personal Notes with #{notes_tool.documents.count} documents"

  # ---------------------------------------------------------------------------
  # 11. Recipes — Todos (Sophie & Priya)
  # ---------------------------------------------------------------------------
  recipes_tool = Tool.create!(
    name: "Recipes",
    owner: sophie,
    tool_type: ToolType.find_by!(slug: "todos")
  )
  add_collaborators(recipes_tool, [priya])

  recipe_list = recipes_tool.todo_lists.first
  recipe_list.update!(title: "Recipe Development", created_by: sophie, updated_by: sophie)

  recipe_list.items.create!(title: "Cosmic Crunch v3 — reduce honey by 10%, add sea salt flakes", position: 0, completed_at: 5.days.ago, created_by: sophie, updated_by: sophie)
  recipe_list.items.create!(title: "Nebula Bites — test 80% cacao instead of 72%", position: 1, completed_at: 3.days.ago, created_by: sophie, updated_by: sophie)
  recipe_list.items.create!(title: "Orbit Rings — experiment with smoked paprika variation", position: 2, assigned_user: sophie, created_by: sophie, updated_by: sophie)
  r1 = recipe_list.items.create!(title: "Develop vegan Nebula Bites alternative", position: 3, assigned_user: priya, due_date: 10.days.from_now, created_by: sophie, updated_by: sophie)
  r1.update!(description: "<p>Use coconut milk powder instead of dairy. Need to test if the chili flavor still comes through.</p>")
  recipe_list.items.create!(title: "Test shelf life — 6 month stability check on all flavors", position: 4, assigned_user: sophie, due_date: 14.days.from_now, created_by: sophie, updated_by: sophie)

  puts "  Created Recipes with #{recipe_list.items.count} items"

  # ---------------------------------------------------------------------------
  # 12. Dev Notes — Docs (Jake only)
  # ---------------------------------------------------------------------------
  dev_docs_tool = Tool.create!(
    name: "Dev Notes",
    owner: jake,
    tool_type: ToolType.find_by!(slug: "docs")
  )

  d1 = dev_docs_tool.documents.create!(title: "Store Architecture", created_by: jake, updated_by: jake, last_edited_at: 1.day.ago)
  d1.update!(content: <<~HTML)
    <h1>Moonshot Snacks — Store Architecture</h1>
    <h2>Stack</h2>
    <ul>
      <li>Frontend: Next.js + Tailwind (deployed on Vercel)</li>
      <li>Backend: Rails API (deployed on Render)</li>
      <li>Payments: Stripe Checkout</li>
      <li>Email: Resend for transactional, Mailchimp for marketing</li>
      <li>Database: PostgreSQL on Neon</li>
    </ul>
    <h2>TODO</h2>
    <ul>
      <li>Add webhook handler for Stripe events</li>
      <li>Set up order confirmation emails</li>
      <li>Add inventory tracking (we have 500 units to start)</li>
      <li>Implement discount codes for launch week</li>
    </ul>
    <h2>Notes</h2>
    <p>Sophie keeps asking if we can accept "space credits." I keep telling her that's not a real currency. She keeps insisting it will be by 2030.</p>
  HTML

  puts "  Created Dev Notes with #{dev_docs_tool.documents.count} document"

  # ---------------------------------------------------------------------------
  # Sidebar Groups (for Sophie)
  # ---------------------------------------------------------------------------
  launch_group = sophie.sidebar_groups.create!(name: "Launch", position: 0)
  Sidebar::Membership.create!(group: launch_group, tool: launch_board_tool, position: 0)
  Sidebar::Membership.create!(group: launch_group, tool: docs_tool, position: 1)
  Sidebar::Membership.create!(group: launch_group, tool: tasks_tool, position: 2)

  team_group = sophie.sidebar_groups.create!(name: "Team", position: 1)
  Sidebar::Membership.create!(group: team_group, tool: chat_tool, position: 0)
  Sidebar::Membership.create!(group: team_group, tool: files_tool, position: 1)
  Sidebar::Membership.create!(group: team_group, tool: room_tool, position: 2)

  puts "  Created sidebar groups: #{sophie.sidebar_groups.pluck(:name).join(', ')}"

  puts "\nDemo data seeded successfully!"
  puts "  Log in as: sophie@moonshot-snacks.com / password123"
  puts "  Other users: marcus@, priya@, jake@ (same password)"
end
