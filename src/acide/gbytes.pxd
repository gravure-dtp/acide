# gbytes.pxd
#distutils: libraries = glib-2.0
#distutils: include_dirs = /usr/include/glib-2.0

cdef extern from "glib-unix.h":
    ctypedef unsigned int gsize

    ctypedef int gint
    ctypedef unsigned int guint
    ctypedef gint gboolean
    ctypedef void* gpointer
    ctypedef const void* gconstpointer
    ctypedef void (*GDestroyNotify)(gpointer data)

    ctypedef struct GBytes

    GBytes* g_bytes_new(gconstpointer data, gsize size)
    GBytes* g_bytes_new_take(gpointer data, gsize size)
    GBytes* g_bytes_new_static(gconstpointer data, gsize size)
    GBytes* g_bytes_new_with_free_func(
        gconstpointer data, gsize size, GDestroyNotify free_func,
        gpointer user_data
    )
    GBytes* g_bytes_new_from_bytes(
        GBytes *bytes, gsize offset, gsize length
    )
    gconstpointer g_bytes_get_data(GBytes *bytes, gsize *size)
    gsize g_bytes_get_size(GBytes *bytes)
    GBytes* g_bytes_ref(GBytes *bytes)
    void g_bytes_unref(GBytes *bytes)
    gpointer g_bytes_unref_to_data(GBytes *bytes, gsize *size)
    # GByteArray* g_bytes_unref_to_array(GBytes *bytes)
    guint g_bytes_hash(gconstpointer bytes)
    gboolean g_bytes_equal(gconstpointer bytes1, gconstpointer bytes2)
    gint g_bytes_compare(gconstpointer bytes1, gconstpointer bytes2)
    gconstpointer g_bytes_get_region(
        GBytes *bytes, gsize element_size, gsize offset, gsize n_elements
    )
