# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'class hypervisor:' do
  context 'with default settings' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<~PUPPET
          class { 'hypervisor':
          }
        PUPPET
      end
    end

    describe package('netplan.io') do
      it { is_expected.to be_absent }
    end
  end
end
