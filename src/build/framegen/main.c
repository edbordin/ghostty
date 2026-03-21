#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <errno.h>
#include <zlib.h>

#define SEPARATOR '\x01'

static int strcmp_ptr(const void *a, const void *b) {
    return strcmp(*(const char *const *)a, *(const char *const *)b);
}

/// Collect *.txt basenames in frames_dir, sorted like scandir+alphasort would.
/// On success sets *out_names (malloc'd array of malloc'd strings) and *out_count.
/// On failure returns -1; *out_names undefined.
static int collect_txt_names(const char *frames_dir, char ***out_names, int *out_count) {
    DIR *d = opendir(frames_dir);
    if (!d) {
        return -1;
    }

    char **names = NULL;
    size_t n = 0;
    size_t cap = 0;

    struct dirent *entry;
    while ((entry = readdir(d)) != NULL) {
        const char *name = entry->d_name;
        if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) continue;
        size_t len = strlen(name);
        if (len <= 4 || strcmp(name + len - 4, ".txt") != 0) continue;

        if (n >= cap) {
            cap = cap ? cap * 2 : 16;
            char **nn = realloc(names, cap * sizeof(char *));
            if (!nn) {
                closedir(d);
                for (size_t i = 0; i < n; i++) free(names[i]);
                free(names);
                return -1;
            }
            names = nn;
        }
        names[n] = strdup(name);
        if (!names[n]) {
            closedir(d);
            for (size_t i = 0; i < n; i++) free(names[i]);
            free(names);
            return -1;
        }
        n++;
    }
    closedir(d);

    if (n == 0) {
        free(names);
        *out_names = NULL;
        *out_count = 0;
        return 0;
    }

    qsort(names, n, sizeof(char *), strcmp_ptr);
    *out_names = names;
    *out_count = (int)n;
    return 0;
}

static void free_txt_names(char **names, int count) {
    if (!names) return;
    for (int i = 0; i < count; i++) {
        free(names[i]);
    }
    free(names);
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
        fclose(f);
        return NULL;
    }

    if (fread(buf, 1, size, f) != (size_t)size) {
        fprintf(stderr, "Failed to read %s\n", path);
        free(buf);
        fclose(f);
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

    char **txt_names;
    int n;
    if (collect_txt_names(frames_dir, &txt_names, &n) < 0) {
        fprintf(stderr, "Failed to scan directory %s: %s\n", frames_dir, strerror(errno));
        return 1;
    }

    if (n == 0) {
        fprintf(stderr, "No frame files found in %s\n", frames_dir);
        return 1;
    }

    size_t total_size = 0;
    char **frame_contents = calloc((size_t)n, sizeof(char *));
    size_t *frame_sizes = calloc((size_t)n, sizeof(size_t));
    if (!frame_contents || !frame_sizes) {
        fprintf(stderr, "Out of memory\n");
        free_txt_names(txt_names, n);
        free(frame_contents);
        free(frame_sizes);
        return 1;
    }

    for (int i = 0; i < n; i++) {
        char path[4096];
        snprintf(path, sizeof(path), "%s/%s", frames_dir, txt_names[i]);

        frame_contents[i] = read_file(path, &frame_sizes[i]);
        if (!frame_contents[i]) {
            for (int j = 0; j < i; j++) free(frame_contents[j]);
            free_txt_names(txt_names, n);
            free(frame_contents);
            free(frame_sizes);
            return 1;
        }

        total_size += frame_sizes[i];
        if (i < n - 1) total_size++;
    }

    free_txt_names(txt_names, n);

    char *joined = malloc(total_size);
    if (!joined) {
        fprintf(stderr, "Failed to allocate joined buffer\n");
        for (int i = 0; i < n; i++) free(frame_contents[i]);
        free(frame_contents);
        free(frame_sizes);
        return 1;
    }

    size_t offset = 0;
    for (int i = 0; i < n; i++) {
        memcpy(joined + offset, frame_contents[i], frame_sizes[i]);
        offset += frame_sizes[i];
        if (i < n - 1) {
            joined[offset++] = SEPARATOR;
        }
    }

    for (int i = 0; i < n; i++) free(frame_contents[i]);
    free(frame_contents);
    free(frame_sizes);

    uLongf compressed_size = compressBound((uLong)total_size);
    unsigned char *compressed = malloc(compressed_size);
    if (!compressed) {
        fprintf(stderr, "Failed to allocate compression buffer\n");
        free(joined);
        return 1;
    }

    z_stream stream = {0};
    stream.next_in = (unsigned char *)joined;
    stream.avail_in = (uInt)total_size;
    stream.next_out = compressed;
    stream.avail_out = compressed_size;

    // Use -MAX_WBITS for raw DEFLATE (no zlib wrapper)
    int ret = deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY);
    if (ret != Z_OK) {
        fprintf(stderr, "deflateInit2 failed: %d\n", ret);
        free(joined);
        free(compressed);
        return 1;
    }

    ret = deflate(&stream, Z_FINISH);
    if (ret != Z_STREAM_END) {
        fprintf(stderr, "deflate failed: %d\n", ret);
        deflateEnd(&stream);
        free(joined);
        free(compressed);
        return 1;
    }

    compressed_size = stream.total_out;
    deflateEnd(&stream);
    free(joined);

    FILE *out = fopen(output_file, "wb");
    if (!out) {
        fprintf(stderr, "Failed to create %s: %s\n", output_file, strerror(errno));
        free(compressed);
        return 1;
    }

    if (fwrite(compressed, 1, compressed_size, out) != compressed_size) {
        fprintf(stderr, "Failed to write compressed data\n");
        fclose(out);
        free(compressed);
        return 1;
    }

    fclose(out);
    free(compressed);

    return 0;
}
