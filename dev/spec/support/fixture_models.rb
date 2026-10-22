# ActiveRecord models for ShortcutPlanner discovery. Defined once at load (never
# per example) so ActiveRecord::Base.descendants stays deterministic; defining an
# AR subclass needs no database connection.
module DevFixtures
  module Chorus
    class Agent < ActiveRecord::Base; end
    class AgentProfile < ActiveRecord::Base; end
    class Artifact < ActiveRecord::Base; end
    class Skill < ActiveRecord::Base; end

    class Source < ActiveRecord::Base
      class Git < ActiveRecord::Base; end # nested: must be skipped
    end

    class Base < ActiveRecord::Base
      self.abstract_class = true # abstract: must be skipped
    end

    class Helper; end # not a model: must be skipped
  end

  module Curry
    class Agent < ActiveRecord::Base; end # collides with Chorus::Agent under a shared letter
    class Cart < ActiveRecord::Base; end
  end

  module ChorusExtra # shares the "Chorus" name prefix
    class Thing < ActiveRecord::Base; end
  end

  module Empty; end

  class Tenant < ActiveRecord::Base; end
end
