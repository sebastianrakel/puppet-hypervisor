# frozen_string_literal: true

require 'spec_helper'

describe 'hypervisor' do
  on_supported_os.each do |os, facts|
    context "on #{os} with default settings" do
      let(:facts) do
        facts
      end

      it { is_expected.to compile.with_all_deps }
    end
  end
end
