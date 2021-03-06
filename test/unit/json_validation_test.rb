require_relative "../simplecov"
require_relative '../../lib/fhir_models'

require 'fileutils'
require 'pry'
require 'minitest/autorun'
require 'bundler/setup'
require 'test/unit'

class JsonValidationTest < Test::Unit::TestCase
 
  # turn off the ridiculous warnings
  $VERBOSE=nil

  ERROR_DIR = File.join('errors', 'JsonValidationTest')
  EXAMPLE_ROOT = File.join('examples','json')

  # Automatically generate one test method per example file
  example_files = File.join(EXAMPLE_ROOT, '**', '*.json')

  # Create a blank folder for the errors
  FileUtils.rm_rf(ERROR_DIR) if File.directory?(ERROR_DIR)
  FileUtils.mkdir_p ERROR_DIR

  Dir.glob(example_files).each do | example_file |
    example_name = File.basename(example_file, ".json")
    define_method("test_json_validation_#{example_name}") do
      run_json_validation_test(example_file, example_name)
    end
  end

  def run_json_validation_test(example_file, example_name)
    input_json = File.read(example_file)
    resource = FHIR::Json.from_json(input_json)
    errors = resource.validate
    if !errors.empty?
      File.open("#{ERROR_DIR}/#{example_name}.err", 'w:UTF-8') {|file| file.write(JSON.pretty_unparse(errors))}
      File.open("#{ERROR_DIR}/#{example_name}.json", 'w:UTF-8') {|file| file.write(input_json)}      
    end
    assert errors.empty?, "Resource failed to validate."
  end

end
