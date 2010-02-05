require "rubygems"
require "test/unit"

$:.unshift File.dirname(__FILE__) + "/../../lib"
require "init"

connection = Mongo::Connection.new
Mongoid.database = connection.db('state_machine_test')

class Conversation
  include Mongoid::Document
  include Mongoid::StateMachine

  attr_writer   :can_close
  attr_accessor :read_enter, :read_exit,
                :needs_attention_enter, :needs_attention_after,
                :read_after_first, :read_after_second,
                :closed_after

  field :state
  field :state_machine

  # How's THAT for self-documenting? ;-)
  def always_true
    true
  end

  def can_close?
    !!@can_close
  end

  def read_enter_action
    self.read_enter = true
  end

  def read_after_first_action
    self.read_after_first = true
  end

  def read_after_second_action
    self.read_after_second = true
  end

  def closed_after_action
    self.closed_after = true
  end
end

class Mongoid::StateMachineTest < Test::Unit::TestCase
  include Mongoid::StateMachine

  def after
    Conversation.destroy_all
  end

  def teardown
    Conversation.class_eval do
      write_inheritable_attribute :states, {}
      write_inheritable_attribute :initial_state, nil
      write_inheritable_attribute :transition_table, {}
      write_inheritable_attribute :event_table, {}
      write_inheritable_attribute :state_column, "state"

      # Clear out any callbacks that were set by state_machine.
      write_inheritable_attribute :before_create, []
      write_inheritable_attribute :after_create, []
    end
  end

  def test_no_initial_value_raises_exception
    assert_raises(NoInitialState) do
      Conversation.class_eval do
        state_machine
      end
    end
  end

  def test_state_column
    Conversation.class_eval do
      state_machine :initial => :needs_attention, :column => "state_machine"
      state :needs_attention
    end

    assert_equal "state_machine", Conversation.state_column
  end

  def test_initial_state_value
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
    end

    assert_equal :needs_attention, Conversation.initial_state
  end

  def test_initial_state
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
    end

    c = Conversation.create!
    assert_equal :needs_attention, c.current_state
    assert c.needs_attention?
  end

  def test_states_were_set
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
      state :read
      state :closed
      state :awaiting_response
      state :junk
    end

    [:needs_attention, :read, :closed, :awaiting_response, :junk].each do |state|
      assert Conversation.states.include?(state)
    end
  end

  def test_query_methods_created
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
      state :read
      state :closed
      state :awaiting_response
      state :junk
    end

    c = Conversation.create!
    [:needs_attention?, :read?, :closed?, :awaiting_response?, :junk?].each do |query|
      assert c.respond_to?(query)
    end
  end

  def test_event_methods_created
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
      state :read
      state :closed
      state :awaiting_response
      state :junk

      event(:new_message) {}
      event(:view) {}
      event(:reply) {}
      event(:close) {}
      event(:junk, :note => "finished") {}
      event(:unjunk) {}
    end

    c = Conversation.create!
    [:new_message!, :view!, :reply!, :close!, :junk!, :unjunk!].each do |event|
      assert c.respond_to?(event)
    end
  end

  def test_transition_table
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
      state :read
      state :closed
      state :awaiting_response
      state :junk

      event :new_message do
        transitions :to => :needs_attention, :from => [:read, :closed, :awaiting_response]
      end
    end

    tt = Conversation.transition_table
    assert tt[:new_message].include?(SupportingClasses::StateTransition.new(:from => :read, :to => :needs_attention))
    assert tt[:new_message].include?(SupportingClasses::StateTransition.new(:from => :closed, :to => :needs_attention))
    assert tt[:new_message].include?(SupportingClasses::StateTransition.new(:from => :awaiting_response, :to => :needs_attention))
  end

  def test_next_state_for_event
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
      state :read

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end
    end

    c = Conversation.create!
    assert_equal :read, c.next_state_for_event(:view)
  end

  def test_change_state
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
      state :read

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end
    end

    c = Conversation.create!
    c.view!
    assert c.read?
  end

  def test_can_go_from_read_to_closed_because_guard_passes
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
      state :read
      state :closed
      state :awaiting_response

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end

      event :reply do
        transitions :to => :awaiting_response, :from => [:read, :closed]
      end

      event :close do
        transitions :to => :closed, :from => [:read, :awaiting_response], :guard => lambda { |o| o.can_close? }
      end
    end

    c = Conversation.create!
    c.can_close = true
    c.view!
    c.reply!
    c.close!
    assert_equal :closed, c.current_state
  end

  def test_cannot_go_from_read_to_closed_because_of_guard
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
      state :read
      state :closed
      state :awaiting_response

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end

      event :reply do
        transitions :to => :awaiting_response, :from => [:read, :closed]
      end

      event :close do
        transitions :to => :closed, :from => [:read, :awaiting_response], :guard => lambda { |o| o.can_close? }
        transitions :to => :read, :from => [:read, :awaiting_response], :guard => :always_true
      end
    end

    c = Conversation.create!
    c.can_close = false
    c.view!
    c.reply!
    c.close!
    assert_equal :read, c.current_state
  end

  def test_ignore_invalid_events
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
      state :read
      state :closed
      state :awaiting_response
      state :junk

      event :new_message do
        transitions :to => :needs_attention, :from => [:read, :closed, :awaiting_response]
      end

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end

      event :junk, :note => "finished" do
        transitions :to => :junk, :from => [:read, :closed, :awaiting_response]
      end
    end

    c = Conversation.create
    c.view!
    c.junk!

    # This is the invalid event
    c.new_message!
    assert_equal :junk, c.current_state
  end

  def test_entry_action_executed
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
      state :read, :enter => :read_enter_action

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end
    end

    c = Conversation.create!
    c.read_enter = false
    c.view!
    assert c.read_enter
  end

  def test_after_actions_executed
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
      state :closed, :after => :closed_after_action
      state :read, :enter => :read_enter_action,
      :exit  => Proc.new { |o| o.read_exit = true },
      :after => [:read_after_first_action, :read_after_second_action]

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end

      event :close do
        transitions :to => :closed, :from => [:read, :awaiting_response]
      end
    end

    c = Conversation.create!

    c.read_after_first = false
    c.read_after_second = false
    c.closed_after = false

    c.view!
    assert c.read_after_first
    assert c.read_after_second

    c.can_close = true
    c.close!

    assert c.closed_after
    assert_equal :closed, c.current_state
  end

  def test_after_actions_not_run_on_loopback_transition
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
      state :closed, :after => :closed_after_action
      state :read, :after => [:read_after_first_action, :read_after_second_action]

      event :view do
        transitions :to => :read, :from => :needs_attention
      end

      event :close do
        transitions :to => :closed, :from => :read
      end
    end

    c = Conversation.create!

    c.view!
    c.read_after_first = false
    c.read_after_second = false
    c.view!

    assert !c.read_after_first
    assert !c.read_after_second

    c.can_close = true

    c.close!
    c.closed_after = false
    c.close!

    assert !c.closed_after
  end

  def test_exit_action_executed
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :junk
      state :needs_attention
      state :read, :exit => lambda { |o| o.read_exit = true }

      event :view do
        transitions :to => :read, :from => :needs_attention
      end

      event :junk, :note => "finished" do
        transitions :to => :junk, :from => :read
      end
    end

    c = Conversation.create!
    c.read_exit = false
    c.view!
    c.junk!
    assert c.read_exit
  end

  def test_entry_and_exit_not_run_on_loopback_transition
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention
      state :read, :exit => lambda { |o| o.read_exit = true }

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end
    end

    c = Conversation.create!
    c.view!
    c.read_enter = false
    c.read_exit  = false
    c.view!
    assert !c.read_enter
    assert !c.read_exit
  end

  def test_entry_and_after_actions_called_for_initial_state
    Conversation.class_eval do
      state_machine :initial => :needs_attention
      state :needs_attention, :enter => lambda { |o| o.needs_attention_enter = true },
      :after => lambda { |o| o.needs_attention_after = true }
    end

    c = Conversation.create!
    assert c.needs_attention_enter
    assert c.needs_attention_after
  end

  def test_run_transition_action_is_private
    Conversation.class_eval do

      state_machine :initial => :needs_attention
      state :needs_attention
    end

    c = Conversation.create!
    assert_raises(NoMethodError) { c.run_transition_action :foo }
  end

  def test_can_access_events_via_event_table
    Conversation.class_eval do
      state_machine :initial => :needs_attention, :column => "state_machine"
      state :needs_attention
      state :junk

      event :junk, :note => "finished" do
        transitions :to => :junk, :from => :needs_attention
      end
    end

    event = Conversation.event_table[:junk]
    assert_equal :junk, event.name
    assert_equal "finished", event.opts[:note]
  end

  def test_custom_state_values
    Conversation.class_eval do
      state_machine :initial => "NEEDS_ATTENTION", :column => "state_machine"
      state :needs_attention, :value => "NEEDS_ATTENTION"
      state :read, :value => "READ"

      event :view do
        transitions :to => "READ", :from => ["NEEDS_ATTENTION", "READ"]
      end
    end

    c = Conversation.create!
    assert_equal "NEEDS_ATTENTION", c.state_machine
    assert c.needs_attention?
    c.view!
    assert_equal "READ", c.state_machine
    assert c.read?
  end
end
