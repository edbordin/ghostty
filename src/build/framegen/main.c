#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <errno.h>
#include <zlib.h>

#define SEPARATOR '\x01'
#define CHUNK_SIZE 16384

static int filter_frames(const struct dirent *entry) {
    const char *name = entry->d_name;
    size_t len = strlen(name);
    return len > 4 && strcmp(name + len - 4, ".txt") == 0;
}

static int compare_frames(const struct dirent **a, const struct dirent **b) {
    return strcmp((*a)->d_name, (*b)->d_name);
}

typedef struct {
    char *name;
} frame_entry;

static int compare_frame_entries(const void *a, const void *b) {
    const frame_entry *fa = (const frame_entry *)a;
    const frame_entry *fb = (const frame_entry *)b;
    return strcmp(fa->name, fb->name);
}

static char *dup_string(const char *s) {
    size_t len = strlen(s);
    char *out = (char *)malloc(len + 1);
    if (!out) {
        return NULL;
    }
    memcpy(out, s, len + 1);
    return out;
}

static char *read_file(const char *path, size_t *out_size) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "Failed to open %s: %s\n", path, strerror(errno));
        return NULL;
    }

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *buf = malloc(size);
    if (!buf) {
        return NULL;
    }

    if (fread(buf, 1, size, f) != (size_t)size) {
        fprintf(stderr, "Failed to read %s\n", path);
        return NULL;
    }

    fclose(f);
    *out_size = size;
    return buf;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <frames_dir> <output_file>\n", argv[0]);
        return 1;
    }

    const char *frames_dir = argv[1];
    const char *output_file = argv[2];

    DIR *dir = opendir(frames_dir);
    if (!dir) {
        fprintf(stderr, "Failed to scan directory %s: %s\n", frames_dir, strerror(errno));
        return 1;
    }

    size_t count = 0;
    size_t capacity = 16;
    frame_entry *entries = (frame_entry *)calloc(capacity, sizeof(frame_entry));
    if (!entries) {
        fprintf(stderr, "Failed to allocate frame list\n");
        closedir(dir);
        return 1;
    }

    struct dirent *entry = NULL;
    while ((entry = readdir(dir)) != NULL) {
        if (!filter_frames(entry)) {
            continue;
        }

        if (count == capacity) {
            size_t new_capacity = capacity * 2;
            frame_entry *grown = (frame_entry *)realloc(entries, new_capacity * sizeof(frame_entry));
            if (!grown) {
                fprintf(stderr, "Failed to grow frame list\n");
                closedir(dir);
                return 1;
            }
            entries = grown;
            capacity = new_capacity;
        }

        entries[count].name = dup_string(entry->d_name);
        if (!entries[count].name) {
            fprintf(stderr, "Failed to copy frame name\n");
            closedir(dir);
            return 1;
        }
        count++;
    }

    closedir(dir);

    if (count == 0) {
        fprintf(stderr, "No frame files found in %s\n", frames_dir);
        return 1;
    }

    qsort(entries, count, sizeof(frame_entry), compare_frame_entries);

    size_t total_size = 0;
    char **frame_contents = calloc(count, sizeof(char*));
    size_t *frame_sizes = calloc(count, sizeof(size_t));

    for (size_t i = 0; i < count; i++) {
        char path[4096];
        snprintf(path, sizeof(path), "%s/%s", frames_dir, entries[i].name);
        
        frame_contents[i] = read_file(path, &frame_sizes[i]);
        if (!frame_contents[i]) {
            return 1;
        }
        
        total_size += frame_sizes[i];
        if (i < count - 1) total_size++;
    }

    char *joined = malloc(total_size);
    if (!joined) {
        fprintf(stderr, "Failed to allocate joined buffer\n");
        return 1;
    }

    size_t offset = 0;
    for (size_t i = 0; i < count; i++) {
        memcpy(joined + offset, frame_contents[i], frame_sizes[i]);
        offset += frame_sizes[i];
        if (i < count - 1) {
            joined[offset++] = SEPARATOR;
        }
    }

    uLongf compressed_size = compressBound(total_size);
    unsigned char *compressed = malloc(compressed_size);
    if (!compressed) {
        fprintf(stderr, "Failed to allocate compression buffer\n");
        return 1;
    }

    z_stream stream = {0};
    stream.next_in = (unsigned char*)joined;
    stream.avail_in = total_size;
    stream.next_out = compressed;
    stream.avail_out = compressed_size;

    // Use -MAX_WBITS for raw DEFLATE (no zlib wrapper)
    int ret = deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY);
    if (ret != Z_OK) {
        fprintf(stderr, "deflateInit2 failed: %d\n", ret);
        return 1;
    }

    ret = deflate(&stream, Z_FINISH);
    if (ret != Z_STREAM_END) {
        fprintf(stderr, "deflate failed: %d\n", ret);
        deflateEnd(&stream);
        return 1;
    }

    compressed_size = stream.total_out;
    deflateEnd(&stream);
    
    FILE *out = fopen(output_file, "wb");
    if (!out) {
        fprintf(stderr, "Failed to create %s: %s\n", output_file, strerror(errno));
        return 1;
    }

    if (fwrite(compressed, 1, compressed_size, out) != compressed_size) {
        fprintf(stderr, "Failed to write compressed data\n");
        return 1;
    }

    fclose(out);

    for (size_t i = 0; i < count; i++) {
        free(entries[i].name);
        free(frame_contents[i]);
    }
    free(entries);
    free(frame_contents);
    free(frame_sizes);
    free(joined);
    free(compressed);

    return 0;
}
