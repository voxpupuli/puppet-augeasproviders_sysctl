require 'spec_helper'

sysctl_type = Puppet::Type.type(:sysctl)

describe sysctl_type do
  context 'when setting parameters' do
    describe 'the name parameter' do
      it 'is a valid parameter' do
        resource = sysctl_type.new name: 'foo'
        expect(resource[:name]).to eq('foo')
      end
    end

    describe 'the val property' do
      it 'is a valid property' do
        resource = sysctl_type.new name: 'foo', val: 'foo'
        expect(resource[:val]).to eq('foo')
      end

      it 'is munged to a string' do
        resource = sysctl_type.new name: 'foo', val: 42
        expect(resource[:val]).to eq('42')
      end
    end

    describe 'the value property' do
      it 'is a valid property' do
        resource = sysctl_type.new name: 'foo', value: 'foo'
        expect(resource[:value]).to eq('foo')
      end

      it 'is munged to a string' do
        resource = sysctl_type.new name: 'foo', value: 42
        expect(resource[:value]).to eq('42')
      end
    end

    describe 'the target parameter' do
      it 'is a valid parameter' do
        resource = sysctl_type.new name: 'foo', target: '/foo/bar'
        expect(resource[:target]).to eq('/foo/bar')
      end
    end

    describe 'the apply parameter' do
      it 'is a valid parameter' do
        resource = sysctl_type.new name: 'foo', apply: :false
        expect(resource[:apply]).to eq(:false)
      end

      it 'defaults to true' do
        resource = sysctl_type.new name: 'foo'
        expect(resource[:apply]).to eq(:true)
      end

      it 'is munged as a boolean' do
        resource = sysctl_type.new name: 'foo', apply: 'true'
        expect(resource[:apply]).to eq(:true)
      end
    end

    describe 'the persist parameter' do
      it 'is a valid parameter' do
        resource = sysctl_type.new name: 'foo', persist: :false
        expect(resource[:persist]).to eq(:false)
      end

      it 'defaults to true' do
        resource = sysctl_type.new name: 'foo'
        expect(resource[:persist]).to eq(:true)
      end

      it 'is munged as a boolean' do
        resource = sysctl_type.new name: 'foo', persist: 'true'
        expect(resource[:persist]).to eq(:true)
      end
    end
  end
end
