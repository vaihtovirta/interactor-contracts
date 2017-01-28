require "dry-validation"
require "interactor"
require "interactor/contracts/breach"
require "interactor/contracts/errors"

module Interactor
  # Create a contract for your interactor that specifies what it expects as
  # inputs.
  module Contracts
    # Called when the module is included into another class or module.
    #
    # @private
    # @param [Class, Module] descendant the including class or module
    def self.included(descendant)
      unless descendant.ancestors.include?(Interactor)
        fail NotAnInteractor, "#{descendant} does not include `Interactor'"
      end
      descendant.extend(ClassMethods)
    end

    private

    # Checks for a breach of contracts against the context's data and applies
    # the consequences if there is a breach.
    #
    # @private
    # @param [#call] contracts a callable object
    # @return [void]
    def enforce_contracts(contracts)
      result = contracts.call(context.to_h)

      unless result.success?
        breached_terms = result.messages.map do |property, messages|
          Breach.new(property, messages)
        end
        self.class.consequences.each do |handler|
          instance_exec(breached_terms, &handler)
        end
      end
    end

    # Defines the class-level DSL that enables Interactor contracts.
    module ClassMethods
      # The assurances the Interactor will fulfill.
      #
      # @return [Dry::Validations::Schema] the assurances schema
      def assurances
        @assurances ||= Class.new(Dry::Validation::Schema)
      end

      # Defines the assurances of an Interactor and creates an after hook to
      # validate the output when called.
      #
      # @example
      #
      #   class CreatePerson
      #     include Interactor
      #     include Interactor::Contracts
      #
      #     assures do
      #       required(:person).filled
      #     end
      #
      #     def call
      #       context.person = Person.new
      #     end
      #   end
      # @param [Block] block the block defining the assurances
      # @return [void]
      def assures(&block)
        self.assurances = extend_schema(assurances, &block)
        define_assurances_hook
      end

      # The consequences for the contract. When no consequences have been
      # defined, it defaults to an array containing the default consequence.
      #
      # @return [Array<#call>] the consequences for the contract
      def consequences
        if defined_consequences.empty?
          Array(default_consequence)
        else
          defined_consequences
        end
      end

      # The default consequence of a breached contract.
      #
      # @return [#call] the default consequence
      def default_consequence
        ->(_breached_terms) { context.fail! }
      end

      # Defines the expectations of an Interactor and creates a before hook to
      # validate the input when called.
      #
      # @example
      #
      #   class CreatePerson
      #     include Interactor
      #     include Interactor::Contracts
      #
      #     expects do
      #       required(:name).filled
      #     end
      #
      #     def call
      #       context.person = Person.create!(:name => context.name)
      #     end
      #   end
      #
      #   CreatePerson.call(:first_name => "Billy").success?  #=> false
      #   CreatePerson.call(:name => "Billy").success?        #=> true
      #
      # @param [Block] block the block defining the expectations
      # @return [void]
      def expects(&block)
        self.expectations = extend_schema(expectations, &block)
        define_expectations_hook
      end

      # The expectations for arguments passed into the Interactor.
      #
      # @return [Dry::Validations::Schema] the expectations schema
      def expectations
        @expectations ||= Class.new(Dry::Validation::Schema)
      end

      # Defines a consequence that is called when a contract is breached.
      #
      # @example
      #
      #   class CreatePerson
      #     include Interactor
      #     include Interactor::Contracts
      #
      #     expects do
      #       required(:name).filled
      #     end
      #
      #     on_breach do |breaches|
      #       context.fail!(:message => "invalid_#{breaches.first.property}")
      #     end
      #
      #     def call
      #       context.person = Person.create!(:name => context.name)
      #     end
      #   end
      #
      #   CreatePerson.call(:first_name => "Billy").message  #=> "invalid_name"
      #
      # @param [Block] block the validation handler as a block of arity 1.
      # @return [void]
      def on_breach(&block)
        defined_consequences << block
      end

      private

      attr_writer :assurances
      attr_writer :expectations

      # Flags whether the assurances hook has been defined.
      #
      # @!attribute [r] defined_assurances_hook
      #   @return [TrueClass, FalseClass] true if the hook is defined
      attr_reader :defined_assurances_hook
      alias_method :defined_assurances_hook?, :defined_assurances_hook

      # Flags whether the expectations hook has been defined.
      #
      # @!attribute [r] defined_assurances_hook
      #   @return [TrueClass, FalseClass] true if the hook is defined
      attr_reader :defined_expectations_hook
      alias_method :defined_expectations_hook?, :defined_expectations_hook

      # Defines an after hook that validates the Interactor's output against
      # its contract.
      #
      # @raise [Interactor::Failure] if the input fails to meet its contract.
      # @return [void]
      def define_assurances_hook
        return if defined_assurances_hook?

        after { enforce_contracts(self.class.assurances.new) }

        @defined_assurances_hook = true
      end

      # Defines a before hook that validates the Interactor's input against its
      # contract.
      #
      # @raise [Interactor::Failure] if the input fails to meet its contract.
      # @return [void]
      def define_expectations_hook
        return if defined_expectations_hook?

        before { enforce_contracts(self.class.expectations.new) }

        @defined_expectations_hook = true
      end

      # The consequences defined for the contract.
      #
      # @return [Array<#call>] the consequences for the contract
      def defined_consequences
        @defined_consequences ||= []
      end

      def extend_schema(schema = Dry::Validation::Schema, &block)
        Dry::Validation.Schema(schema, {:build => false}, &block)
      end
    end
  end
end
