//
//  SecureMem.h
//  MAI Browser — Secure Memory for Password Protection
//
//  mlock-backed memory that never touches swap disk.
//  Used for banking credentials and sensitive data.
//

#ifndef SECURE_MEM_H
#define SECURE_MEM_H

#include <stddef.h>
#include <stdint.h>

/// Opaque handle to a locked memory region
typedef struct SecureBuffer {
    void*  data;
    size_t length;
    size_t capacity;
} SecureBuffer;

/// Allocate a secure buffer with mlock (memory never swapped to disk).
/// Returns NULL on failure. Caller must call secure_buffer_free().
SecureBuffer* secure_buffer_create(size_t capacity);

/// Write data into the secure buffer. Returns 0 on success, -1 if data exceeds capacity.
int secure_buffer_write(SecureBuffer* buf, const void* src, size_t len);

/// Get read-only pointer to the data. Returns NULL if buffer is NULL.
const void* secure_buffer_data(const SecureBuffer* buf);

/// Get the current data length.
size_t secure_buffer_length(const SecureBuffer* buf);

/// Zero-fill the buffer contents using memset_s (compiler cannot optimize away).
void secure_buffer_zero(SecureBuffer* buf);

/// Zero-fill, munlock, and free the buffer. Sets pointer to NULL.
void secure_buffer_free(SecureBuffer** buf);

#endif /* SECURE_MEM_H */
