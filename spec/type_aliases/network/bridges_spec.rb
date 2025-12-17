# frozen_string_literal: true

require 'spec_helper'

describe 'Hypervisor::Network::Bridges' do
  let(:data) do
    {
      'intern': {
        address_v4: '192.168.122.1/24',
        dhcp_pool_offset: 20,
        dhcp_pool_size: 100
      }
    }
  end

  context 'with valid data' do
    context 'full data' do
      it { is_expected.to allow_value(data) }
    end
  end

  context 'with invalid data' do
    context 'bad strings' do
      let(:bad_strings) do
        {
          network_name: ''
        }
      end

      it { is_expected.not_to allow_value(bad_strings) }
    end
  end
end
