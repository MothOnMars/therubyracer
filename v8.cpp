#include "ruby_data.h"
#include "generic_data.h"
#include "v8_data.h"
#include "v8_context.h"
#include "v8_cxt.h"
#include "v8_standalone.h"

#include <stdio.h>

extern "C" {
    /**
     * ruby init method for the extension
     */
    void Init_v8();
}

VALUE rb_mModule;
VALUE rb_cV8;

extern "C" {
    void Init_v8() {
      
        ruby_call_symbol = ID2SYM(rb_intern("call"));
        ruby_respond_to_ID = rb_intern("respond_to?");
        ruby_proc_class = rb_eval_string("::Proc");
        ruby_method_class = rb_eval_string("::Method");
      
        rb_mModule = rb_define_module("V8");
        
        // context setup
        rb_cV8 = rb_define_class_under(rb_mModule, "Context", rb_cObject);
        rb_define_alloc_func(rb_cV8, v8_context_allocate);
        rb_define_method(rb_cV8, "eval", (VALUE(*)(...)) v8_context_eval, 1);
        rb_define_method(rb_cV8, "[]=", (VALUE(*)(...)) v8_context_inject, 2);
        
        //native module setup
        VALUE rb_mNative = rb_define_module_under(rb_mModule, "N");
        VALUE V8_N_Context = rb_define_class_under(rb_mNative, "Context", rb_cObject);
        rb_define_alloc_func(V8_N_Context, v8_cxt_allocate);
        
        // js object setup
        rb_cV8_JSObject = rb_define_class_under(rb_mModule, "JSObject", rb_cObject);
        rb_define_alloc_func(rb_cV8_JSObject, v8_object_allocate);
        rb_define_method(rb_cV8_JSObject, "[]", (VALUE(*)(...)) v8_object_hash_access, 1);
        rb_define_method(rb_cV8_JSObject, "[]=", (VALUE(*)(...)) v8_object_hash_assignment, 2);
        rb_define_method(rb_cV8_JSObject, "call_something", (VALUE(*)(...)) v8_object_call_something, 1);
        // stand alone methods
        rb_define_singleton_method(rb_mModule, "what_is_this?",(VALUE(*)(...)) v8_what_is_this, 1);
    }
}