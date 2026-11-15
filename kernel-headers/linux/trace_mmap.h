/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
#ifndef _TRACE_MMAP_H_
#define _TRACE_MMAP_H_

#include <linux/types.h>

struct ring_buffer_meta {
	unsigned long	entries;
	unsigned long	overrun;
	unsigned long	read;

	unsigned long	pages_touched;
	unsigned long	pages_lost;
	unsigned long	pages_read;

	__u32		meta_page_size;
	__u32		nr_data_pages;	/* Number of pages in the ring-buffer */

	struct reader_page {
		__u32	id;		/* Reader page ID from 0 to nr_data_pages - 1 */
		__u32	read;		/* Number of bytes read on the reader page */
		unsigned long	lost_events; /* Events lost at the time of the reader swap */
	} reader_page;
};

#endif /* _TRACE_MMAP_H_ */
