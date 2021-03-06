require_relative '../resource'

module Convection
  module DSL
    module Template
      module Resource
        ## Role DSL
        module IAMRole
          def assume_role_policy(policy_name, &block)
            @trust_relationship = Model::Mixin::Policy.new(:name => policy_name, :template => @template)
            trust_relationship.instance_exec(&block) if block
          end

          def policy(policy_name, &block)
            add_policy = Model::Mixin::Policy.new(:name => policy_name, :template => @template)
            add_policy.instance_exec(&block) if block

            policies << add_policy
          end

          ## Create an IAM Instance Profile for this role
          def with_instance_profile(&block)
            profile = Model::Template::Resource::IAMInstanceProfile.new("#{ name }Profile", @template)
            profile.role(self)
            profile.path(path)

            profile.instance_exec(&block) if block
            @instance_profile = profile
            @template.resources[profile.name] = profile
          end

          ## Add a canned trust policy for any AWS service
          def trust_service(name, policy_name = nil, &block)
            policy_name ||= "trust-#{name}-service"
            @trust_relationship = Model::Mixin::Policy.new(:name => policy_name, :template => @template)
            trust_relationship.allow do
              action 'sts:AssumeRole'
              principal :Service => "#{name}.amazonaws.com"
            end
            trust_relationship.instance_exec(&block) if block
          end

          ## Add a canned trust policy for EC2 instances
          def trust_ec2_instances(&block)
            trust_service('ec2', 'trust-ec2-instances', &block)
          end

          ## Add a canned trust policy for Flow Logs
          def trust_flow_logs(&block)
            trust_service('vpc-flow-logs', 'trust-flow-logs', &block)
          end

          ## Add a canned trust policy for EMR
          def trust_emr(&block)
            trust_service('elasticmapreduce', 'trust-emr', &block)
          end

          ## Add a canned trust policy for Cloudtrail
          def trust_cloudtrail(&block)
            trust_service('cloudtrail', 'trust-cloudtrail-instances', &block)
          end

          ## Add a policy to allow instance to self-terminate
          def allow_instance_termination(&block)
            with_instance_profile if instance_profile.nil?

            term_policy = Model::Template::Resource::IAMPolicy.new("#{ name }TerminationPolicy", @template)
            term_policy.policy_name('allow-instance-termination')

            parent_role = self
            term_policy.allow do
              action 'ec2:TerminateInstances'
              resource '*'
              condition :StringEquals => {
                'ec2:InstanceProfile' => get_att(parent_role.instance_profile.name, 'Arn')
              }
            end
            term_policy.role(self)
            term_policy.depends_on(instance_profile)

            term_policy.instance_exec(&block) if block
            @template.resources[term_policy.name] = term_policy
          end
        end
      end
    end
  end

  module Model
    class Template
      class Resource
        ##
        # AWS::IAM::Role
        ##
        class IAMRole < Resource
          include DSL::Template::Resource::IAMRole

          type 'AWS::IAM::Role'
          property :path, 'Path'
          property :policies, 'Policies', :type => :list
          property :managed_policy_arn, 'ManagedPolicyArns', :type => :list
          property :role_name, 'RoleName'
          alias managed_policy managed_policy_arn

          attr_accessor :trust_relationship
          attr_reader :instance_profile

          def render
            super.tap do |r|
              r['Properties']['AssumeRolePolicyDocument'] = trust_relationship.document unless trust_relationship.nil?
            end
          end
        end
      end
    end
  end
end
