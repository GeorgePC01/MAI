//
//  SecureMem.c
//  MAI Browser — Secure Memory for Password Protection
//
//  mlock prevents the kernel from swapping this memory to disk.
//  memset_s guarantees zero-fill even with compiler optimizations.
//

#include "include/SecureMem.h"
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

SecureBuffer* secure_buffer_create(size_t capacity) {
    if (capacity == 0) return NULL;

    SecureBuffer* buf = (SecureBuffer*)malloc(sizeof(SecureBuffer));
    if (!buf) return NULL;

    // Allocate the data region
    buf->data = malloc(capacity);
    if (!buf->data) {
        free(buf);
        return NULL;
    }

    // Lock memory pages — kernel will not swap to disk
    if (mlock(buf->data, capacity) != 0) {
        // mlock failed (e.g., RLIMIT_MEMLOCK exceeded)
        // Still usable but without swap protection — log and continue
        // In practice on macOS this rarely fails for small buffers
    }

    memset(buf->data, 0, capacity);
    buf->length = 0;
    buf->capacity = capacity;
    return buf;
}

int secure_buffer_write(SecureBuffer* buf, const void* src, size_t len) {
    if (!buf || !src) return -1;
    if (len > buf->capacity) return -1;

    // Zero previous content first
    memset_s(buf->data, buf->capacity, 0, buf->capacity);

    memcpy(buf->data, src, len);
    buf->length = len;
    return 0;
}

const void* secure_buffer_data(const SecureBuffer* buf) {
    if (!buf) return NULL;
    return buf->data;
}

size_t secure_buffer_length(const SecureBuffer* buf) {
    if (!buf) return 0;
    return buf->length;
}

void secure_buffer_zero(SecureBuffer* buf) {
    if (!buf || !buf->data) return;
    // memset_s is guaranteed to not be optimized away by the compiler
    memset_s(buf->data, buf->capacity, 0, buf->capacity);
    buf->length = 0;
}

void secure_buffer_free(SecureBuffer** buf_ptr) {
    if (!buf_ptr || !*buf_ptr) return;
    SecureBuffer* buf = *buf_ptr;

    if (buf->data) {
        // Zero-fill before freeing
        memset_s(buf->data, buf->capacity, 0, buf->capacity);
        // Unlock memory pages
        munlock(buf->data, buf->capacity);
        free(buf->data);
    }

    free(buf);
    *buf_ptr = NULL;
}
