module Mongoid
  module StateMachine              #:nodoc:
    
    VERSION = "0.1"
    
    class InvalidState < Exception #:nodoc:
    end
    class NoInitialState < Exception #:nodoc:
    end

    def self.included(base)        #:nodoc:
      base.extend ActMacro
    end

    module SupportingClasses
      # Default transition action.  Always returns true.
      NOOP = lambda { |o| true }

      class State
        attr_reader :name, :value

        def initialize(name, options)
          @name  = name.to_sym
          @value = (options[:value] || @name).to_s
          @after = Array(options[:after])
          @enter = options[:enter] || NOOP
          @exit  = options[:exit] || NOOP
        end

        def entering(record)
          record.send(:run_transition_action, @enter)
        end

        def entered(record)
          @after.each { |action| record.send(:run_transition_action, action) }
        end

        def exited(record)
          record.send(:run_transition_action, @exit)
        end
      end

      class StateTransition
        attr_reader :from, :to, :opts

        def initialize(options)
          @from  = options[:from].to_s
          @to    = options[:to].to_s
          @guard = options[:guard] || NOOP
          @opts  = options
        end

        def guard(obj)
          @guard ? obj.send(:run_transition_action, @guard) : true
        end

        def perform(record)
          return false unless guard(record)
          loopback = record.current_state.to_s == to
          states = record.class.states
          next_state = states[to]
          old_state = states[record.current_state.to_s]

          next_state.entering(record) unless loopback

          next_state.entered(record) unless loopback
          old_state.exited(record) unless loopback

          record.send("#{record.class.state_column}=", next_state.value)
          record.save
        end

        def ==(obj)
          @from == obj.from && @to == obj.to
        end
      end

      class Event
        attr_reader :name
        attr_reader :transitions
        attr_reader :opts

        def initialize(name, opts, transition_table, &block)
          @name = name.to_sym
          @transitions = transition_table[@name] = []
          instance_eval(&block) if block
          @opts = opts
          @opts.freeze
          @transitions.freeze
          freeze
        end

        def next_states(record)
          @transitions.select { |t| t.from == record.current_state.to_s }
        end

        def fire(record)
          next_states(record).each do |transition|
            break true if transition.perform(record)
          end
        end

        def transitions(trans_opts)
          Array(trans_opts[:from]).each do |s|
            @transitions << SupportingClasses::StateTransition.new(trans_opts.merge({:from => s.to_sym}))
          end
        end
      end
    end

    module ActMacro
      # Configuration options are
      #
      # * +column+ - specifies the column name to use for keeping the state (default: state)
      # * +initial+ - specifies an initial state for newly created objects (required)
      def state_machine(options = {})
        class_eval do
          extend ClassMethods
          include InstanceMethods

          raise NoInitialState unless options[:initial]

          class_attribute :states
          class_attribute :initial_state
          class_attribute :transition_table
          class_attribute :event_table
          class_attribute :state_column

          self.states = {}
          self.initial_state = options[:initial]
          self.transition_table = {}
          self.event_table = {}
          self.state_column = options[:column] || 'state'

          before_create               :set_initial_state
          after_create                :run_initial_state_actions
        end
      end
    end

    module InstanceMethods
      def set_initial_state #:nodoc:
        send("#{self.class.state_column}=", self.class.initial_state.to_s)
      end

      def run_initial_state_actions
        initial = self.class.states[self.class.initial_state.to_s]
        initial.entering(self)
        initial.entered(self)
      end

      # Returns the current state the object is in, as a Ruby symbol.
      def current_state
        self.send(self.class.state_column).to_sym
      end

      # Returns what the next state for a given event would be, as a Ruby symbol.
      def next_state_for_event(event)
        ns = next_states_for_event(event)
        ns.empty? ? nil : ns.first.to.to_sym
      end

      def next_states_for_event(event)
        self.class.transition_table[event.to_sym].select do |s|
          s.from == current_state.to_s
        end
      end

      def run_transition_action(action)
        Symbol === action ? self.method(action).call : action.call(self)
      end
      private :run_transition_action
    end

    module ClassMethods
      # Returns an array of all known states.
      def states
        states.keys.collect { |state| state.to_sym }
      end

      # Define an event.  This takes a block which describes all valid transitions
      # for this event.
      #
      # Example:
      #
      # class Order
      #   acts_as_state_machine :initial => :open
      #
      #   state :open
      #   state :closed
      #
      #   event :close_order do
      #     transitions :to => :closed, :from => :open
      #   end
      # end
      #
      # +transitions+ takes a hash where <tt>:to</tt> is the state to transition
      # to and <tt>:from</tt> is a state (or Array of states) from which this
      # event can be fired.
      #
      # This creates an instance method used for firing the event.  The method
      # created is the name of the event followed by an exclamation point (!).
      # Example: <tt>order.close_order!</tt>.
      def event(event, opts={}, &block)
        tt = transition_table

        e = SupportingClasses::Event.new(event, opts, tt, &block)
        event_table[event.to_sym] = e
        define_method("#{event.to_s}!") { e.fire(self) }
      end

      # Define a state of the system. +state+ can take an optional Proc object
      # which will be executed every time the system transitions into that
      # state.  The proc will be passed the current object.
      #
      # Example:
      #
      # class Order
      #   acts_as_state_machine :initial => :open
      #
      #   state :open
      #   state :closed, Proc.new { |o| Mailer.send_notice(o) }
      # end
      def state(name, opts={})
        state = SupportingClasses::State.new(name, opts)
        states[state.value] = state

        define_method("#{state.name}?") { current_state.to_s == state.value }
      end
    end
  end
end