module FHIR
  module Hashable

    def to_hash
      hash = Hash.new
      self.class::METADATA.each do |key,value|
        local_name = key
        local_name = value['local_name'] if value['local_name']
        hash[key] = self.instance_variable_get("@#{local_name}")
        if hash[key].respond_to?(:to_hash)
          hash[key] = hash[key].to_hash
        elsif hash[key].is_a? Array
          hash[key] = Array.new(hash[key]) # copy the array
          hash[key].each_with_index do |item,index|
            hash[key][index] = item.to_hash if item.respond_to?(:to_hash)
          end
        end
      end
      hash.keep_if do |key,value|
        !value.nil? && (  (value.is_a?(Hash) && !value.empty?) || 
                          (value.is_a?(Array) && !value.empty?) || 
                          (!value.is_a?(Hash) && !value.is_a?(Array))
                       )
      end
      hash['resourceType'] = self.resourceType if self.respond_to?(:resourceType)
      hash
    end

    def from_hash(hash)
      # clear the existing variables
      self.class::METADATA.each do |key,value|
        local_name = key
        local_name = value['local_name'] if value['local_name']
        self.instance_variable_set("@#{local_name}",nil)
      end
      # set the variables to the hash values
      hash.each do |key,value|
        key = key.to_s
        meta = self.class::METADATA[key]
        if !meta.nil?
          local_name = key
          local_name = meta['local_name'] if meta['local_name']
          self.instance_variable_set("@#{local_name}",value) rescue nil
          # inflate the value if it isn't a primitive
          klass = Module.const_get("FHIR::#{meta['type']}") rescue nil
          if !klass.nil? && !value.nil?
            # handle array of objects
            if value.is_a?(Array)
              value.map! do |child|
                obj = child
                unless [FHIR::RESOURCES, FHIR::TYPES].flatten.include? child.class.name.gsub('FHIR::','')
                  if child['resourceType']
                    klass = Module.const_get("FHIR::#{child['resourceType']}") rescue nil
                  end
                  begin
                    obj = klass.new(child)
                  rescue Exception => e
                    $LOG.error("Unable to inflate embedded class #{klass}\n#{e.backtrace}")
                  end
                end
                obj
              end
            else # handle single object
              if value['resourceType']
                klass = Module.const_get("FHIR::#{value['resourceType']}") rescue nil
              end
              begin
                obj = klass.new(value)
                value = obj
              rescue Exception => e
                $LOG.error("Unable to inflate embedded class #{klass}\n#{e.backtrace}")
              end
              # if there is only one of these, but cardinality allows more, we need to wrap it in an array.              
              value = [ value ] if(value && (meta['max'] > 1))
            end
            self.instance_variable_set("@#{local_name}",value)
          elsif !FHIR::PRIMITIVES.include?(meta['type']) && meta['type']!='xhtml'
            $LOG.error("Unhandled and unrecognized class/type: #{meta['type']}")
          else
            # primitive
            if value.is_a?(Array)
              # array of primitives
              value.map!{|child| convert_primitive(child,meta)}
              self.instance_variable_set("@#{local_name}",value)
            else
              # single primitive
              value = convert_primitive(value,meta)
              # if there is only one of these, but cardinality allows more, we need to wrap it in an array.              
              value = [ value ] if(value && (meta['max'] > 1))
              self.instance_variable_set("@#{local_name}",value)
            end
          end # !klass && !nil?
        end # !meta.nil?
      end # hash loop
      self
    end

    def convert_primitive(value,meta)
      return value if !value.is_a?(String)

      rval = value
      if meta['type']=='boolean'
        rval = false
        rval = true if value.strip=='true'
      elsif FHIR::PRIMITIVES.include?(meta['type'])
        primitive_meta = FHIR::PRIMITIVES[ meta['type'] ]
        if primitive_meta['type'] == 'number'
          rval = BigDecimal.new(value.to_s)
          if rval.frac==0
            rval = rval.to_i
          else
            rval = rval.to_f
          end
        end # primitive is number
      end # boolean else
      rval
    end

    private :convert_primitive
  end
end
