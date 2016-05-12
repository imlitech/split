require 'spec_helper'
require 'split/experiment_catalog'
require 'split/experiment'
require 'split/user'

describe Split::User do
  let(:user_keys) { { 'link_color' => 'blue' } }
  let(:context) { double(:session => { split:  user_keys }) }
  let(:experiment) { Split::Experiment.new('link_color') }

  before(:each) do
    @subject = described_class.new(context)
  end

  it 'delegates methods correctly' do
    expect(@subject['link_color']).to eq(@subject.user['link_color'])
  end

  context '#cleanup_old_versions!' do
    let(:user_keys) { { 'link_color:1' => 'blue' } }

    it 'removes key if old experiment is found' do
      @subject.cleanup_old_versions!(experiment)
      expect(@subject.keys).to be_empty
    end
  end 

  context '#cleanup_old_experiments!' do
    it 'removes key if experiment is not found' do
      @subject.cleanup_old_experiments!
      expect(@subject.keys).to be_empty
    end

    it 'removes key if experiment has a winner' do
      allow(Split::ExperimentCatalog).to receive(:find).with('link_color').and_return(experiment)
      allow(experiment).to receive(:start_time).and_return(Date.today)
      allow(experiment).to receive(:has_winner?).and_return(true)
      @subject.cleanup_old_experiments!
      expect(@subject.keys).to be_empty
    end

    it 'removes key if experiment has not started yet' do
      allow(Split::ExperimentCatalog).to receive(:find).with('link_color').and_return(experiment)
      allow(experiment).to receive(:has_winner?).and_return(false)
      @subject.cleanup_old_experiments!
      expect(@subject.keys).to be_empty
    end    
  end
end