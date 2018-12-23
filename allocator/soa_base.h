#ifndef ALLOCATOR_SOA_BASE_H
#define ALLOCATOR_SOA_BASE_H

#include "allocator/soa_helper.h"
#include "allocator/soa_field.h"

// User-defined classes should inherit from this class.
template<class AllocatorT>
class SoaBase {
 public:
  using Allocator = AllocatorT;
  using BaseClass = void;
  static const bool kIsAbstract = false;

  __DEV__ uint8_t get_type() const { return AllocatorT::get_type(this); }

  __DEV__ uint8_t get_type() const volatile {
    return AllocatorT::get_type(this);
  }

  template<typename ClassIterT, typename ScanClassT>
  __DEV__ void rewrite_object(AllocatorT* allocator, int num_records) {
    SoaClassHelper<ScanClassT>::template dev_for_all<ClassIterT::FieldUpdater,
                                                     /*IterateBase=*/ true>(
        allocator, static_cast<ScanClassT*>(this), num_records);
  }

  __DEV__ void DBG_print_ptr_decoding() const {
    char* block_ptr = PointerHelper::block_base_from_obj_ptr(this);
    int obj_id = PointerHelper::obj_id_from_obj_ptr(this);
    printf("%p = Block %p  |  Object %i\n", this, block_ptr, obj_id);
  }

  template<typename T>
  __DEV__ T* cast() {
    if (this != nullptr
        && get_type() == AllocatorT::template BlockHelper<T>::kIndex) {
      return static_cast<T*>(this);
    } else {
      return nullptr;
    }
  }

  template<typename T>
  __DEV__ volatile T* cast() volatile {
    if (this != nullptr
        && get_type() == AllocatorT::template BlockHelper<T>::kIndex) {
      return static_cast<volatile T*>(this);
    } else {
      return nullptr;
    }
  }
};

#endif  // ALLOCATOR_SOA_BASE_H
