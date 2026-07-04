require "spec_helper"

RSpec.describe CnfsSupport::Model do
  before do
    stub_const("CnfsOkf::Widget", Class.new do
      include CnfsSupport::Model

      def touch_it(&block)
        instrument(:touch, id: 1, &block)
      end
    end)
  end

  it "provides the Logging mixin (tagged logger)" do
    expect(CnfsOkf::Widget.new).to respond_to(:logger)
    expect(CnfsOkf::Widget.logger.tag).to eq("cnfs_okf")
  end

  it "provides the Instrumentable mixin (instance instrument)" do
    events = []
    sub = ActiveSupport::Notifications.subscribe("cnfs_okf.widget.touch") { |*a| events << a }
    CnfsOkf::Widget.new.touch_it { :ok }
    expect(events.size).to eq(1)
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  it "provides the class-level instrument entry point" do
    expect(CnfsOkf::Widget).to respond_to(:instrument)
  end
end
