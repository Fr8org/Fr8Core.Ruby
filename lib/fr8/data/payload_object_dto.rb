# frozen_string_literal: true
module Fr8
  module Data
    # TODO: Describe this class
    class PayloadObjectDTO < CamelizedJSONCapitalized
      attr_accessor :payload_object

      def initialize(payload_object: [])
        method(__method__).parameters.each do |type, k|
          next unless type.to_s.starts_with?('key')
          v = eval(k.to_s)
          instance_variable_set("@#{k}", v) unless v.nil?
        end
      end

      def from_fr8_json(fr8_json)
        hash = hash_from_fr8_json(fr8_json)

        hash[:payload_object] ||= []
        hash[:payload_object].map! { |kv| KeyValueDTO.from_fr8_json(kv) }

        new(**hash)
      end
    end
  end
end
