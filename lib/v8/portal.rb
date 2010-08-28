
module V8
  class Portal

    def initialize(context)
      @context = context
      @named_property_getter = Interceptor(NamedPropertyGetter)
      @named_property_setter = Interceptor(NamedPropertySetter)
      @named_property_query = nil
      @named_property_deleter = nil
      @named_property_enumerator = Interceptor(NamedPropertyEnumerator)
      
      @indexed_property_getter = Interceptor(IndexedPropertyGetter)
      @indexed_property_setter = Interceptor(IndexedPropertySetter)
      @indexed_property_query = nil
      @indexed_property_deleter = nil
      @indexed_property_enumerator = Interceptor(IndexedPropertyEnumerator)
    end

    def open
      @context.native.enter do
        yield(self)
      end if block_given?
    end

    def rb(value)
      case value
      when V8::C::Function  then peer(value) {V8::Function}
      when V8::C::Array     then peer(value) {V8::Array}
      when V8::C::Object    then peer(value) {V8::Object}
      when V8::C::String    then value.Utf8Value()
      when V8::C::Date      then Time.at(value.NumberValue())
      when V8::C::Value     then nil if value.IsEmpty()
      else
        value
      end
    end

    def v8(value)
      case value
      when V8::Object
        value.instance_eval {@native}
      when String
        C::String::New(value.to_s)
      when Symbol
        C::String::NewSymbol(value.to_s)
      when Proc,Method
        template = C::FunctionTemplate::New() do |arguments|
          rbargs = []
          for i in 0..arguments.Length() - 1
            rbargs << rb(arguments[i])
          end
          rubycall(value, *rbargs)
        end
        return template.GetFunction()
      when ::Array
        C::Array::New(value.length).tap do |a|
          value.each_with_index do |item, i|
            a.Set(i, v8(item))
          end
        end
      when ::Hash
        C::Object::New().tap do |o|
          value.each do |key, value|
            o.Set(v8(key), v8(value))
          end
        end
      when ::Time
        C::Date::New(value)
      when ::Class
        Constructors[value].GetFunction().tap do |f|
          f.SetHiddenValue(C::String::NewSymbol("TheRubyRacer::RubyObject"), C::External::New(value))
        end
      when nil,Numeric,TrueClass,FalseClass, C::Value
        value
      else
        args = C::Array::New(1)
        args.Set(0, C::External::New(value))
        obj = @context.access[value.class].GetFunction().NewInstance(args)
        return obj
      end
    end
    
################################
    def rubyprotect(&blk)
      self.v8(rubyprotect2(&blk))
    end

    def rubyprotect2
      begin
        yield
      rescue Exception => e
        case e
        when SystemExit, NoMemoryError
          raise e
        else
          error = V8::C::Exception::Error(V8::C::String::New(e.message))
          error.SetHiddenValue("TheRubyRacer::Cause", C::External::New(e))
          V8::C::ThrowException(error)
        end
      end
    end

    def rubycall(rubycode, *args, &block)
      rubyprotect do
        rubycode.call(*args, &block)
      end
    end

    def rubysend(obj, message, *args, &block)
      rubyprotect do
        obj.send(message, *args, &block)
      end
    end
    
    def rubytemplate
      C::ObjectTemplate::New().tap do |t|
        setuptemplate(t)
      end
    end
    
    def setuptemplate(t)
      t.SetNamedPropertyHandler(
        @named_property_getter,
        @named_property_setter,
        nil,
        nil,
        @named_property_enumerator
      )
      t.SetIndexedPropertyHandler(
        @indexed_property_getter,
        @indexed_property_setter,
        nil,
        nil,
        @indexed_property_enumerator
      )
    end
################################
    
    private

    def peer(value)
      external = value.GetHiddenValue(C::String::NewSymbol("TheRubyRacer::RubyObject"))
      if external && !external.IsEmpty()
        external.Value()
      else
        yield.new(value, self)
      end
    end

    class Interceptor
      def initialize(portal, context)
        @to = portal
        @context = context
      end

      def intercept(info, retval = nil, &code)
        obj = @to.rb(info.This())
        intercepts = true
        result = @to.rubyprotect do
          dontintercept = proc do
            intercepts = false
          end
          code.call(obj, dontintercept)
        end
        intercepts ? (retval || result) : C::Empty
      end
      
      def access
        @context.access
      end
    end
    
    def Interceptor(cls)
      cls.new self, @context
    end

    class PropertyAttributes
      attr_reader :flags
      def initialize
        @flags = 0
      end

      def read_only
        tap do
          @flags |= V8::C::ReadOnly
        end
      end

      def dont_enum
        tap do
          @flags |= V8::C::DontEnum
        end
      end

      def dont_delete
        tap do
          @flags |= V8::C::DontDelete
        end
      end
    end
    
    class NamedPropertyGetter < Interceptor
      def call(property, info)
        intercept(info) do |obj, dontintercept|
          access.get(obj, @to.rb(property), &dontintercept)
        end
      end
    end

    class NamedPropertySetter < Interceptor
      def call(property, value, info)
        intercept(info, value) do |obj, dontintercept|
          access.set(obj, @to.rb(property), @to.rb(value), &dontintercept)
        end
      end
    end

    class NamedPropertyQuery
      def call(property, info)
        attributes = PropertyAttributes.new
        result = intercept(info) do |obj, dontintercept|
          access.query(obj, @to.rb(property), attributes, &dontintercept)
        end
        return result == C::Empty ? result : C::Integer::New(attributes.flags)
      end
    end

    class NamedPropertyEnumerator < Interceptor
      def call(info)
        intercept(info) do |obj, dontintercept|
          access.names(obj, &dontintercept).to_a
        end
      end
    end
    
    class NamedPropertyDeleter < Interceptor
      def call(property, info)
        intercept(info) do |obj, dontintercept|
          access.delete(obj, property, &dontintercept)
        end
      end
    end

    class IndexedPropertyGetter < Interceptor
      def call(index, info)
        intercept(info) do |obj, dontintercept|
          access.iget(obj, index, &dontintercept)
        end
      end
    end

    class IndexedPropertySetter < Interceptor
      def call(index, value, info)
        intercept(info, value) do |obj, dontintercept|
          access.iset(obj, index, @to.rb(value), &dontintercept)
        end
      end
    end

    class IndexedPropertyQuery < Interceptor
      def call(property, info)
        attributes = PropertyAttributes.new
        result = intercept(info) do |obj, dontintercept|
          access.indices(obj, &dontintercept)
        end
        result == C::Empty ? C::Empty : C::Integer::New(attributes.flags)
      end
    end

    class IndexedPropertyDeleter < Interceptor
      def call(index, info)
        intercept(info) do |obj, dontintercept|
          access.idelete(obj, index, &dontintercept)
        end
      end
    end
    
    class IndexedPropertyEnumerator < Interceptor
      def call(info)
        intercept(info) do |obj, dontintercept|
          access.indices(obj, &dontintercept)
        end
      end
    end
  end
end