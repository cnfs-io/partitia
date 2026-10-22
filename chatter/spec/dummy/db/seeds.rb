# A handful of human participants and one non-human agent, so you can open two
# tabs, "become" different participants, and watch real-time delivery.
%w[Ada Babbage Carol Dijkstra].each do |name|
  Person.find_or_create_by!(name: name)
end

Agent.find_or_create_by!(name: "Support Bot")

puts "Seeded #{Person.count} people and #{Agent.count} agents."
