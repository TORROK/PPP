class Queue {
    array head, tail;
    int size = 0;

    constant DATA = 0;
    constant NEXT = 1;

    int _sizeof() {
	return size;
    }

    int isEmpty() {
        return !head;
    }

    void push(mixed data) {
        if (isEmpty()) {
            head = tail = allocate(2);
            head[DATA] = data;
        } else {
            tail = tail[NEXT] = allocate(2);
            tail[DATA] = data;
        }

	size++;
    }

    mixed shift() {
        mixed data;

        if (isEmpty()) return UNDEFINED;

        data = head[DATA];
        head = head[NEXT];

        if (isEmpty()) tail = 0;

	size--;

        return data;
    }

    void unshift(mixed data) {
        if (isEmpty()) {
            push(data);
        } else {
            array newhead = allocate(2); // uncool, but allows changing of
                                         // DATA and NEXT... as if anybody
                                         // would need that .)

            newhead[DATA] = data;
            newhead[NEXT] = head;
            head = newhead;
        }

	size++;
    }

    mixed cast(string type) {
	if (type == "array") {
	    array out = allocate(sizeof(this));
	    array tmp = head;

	    for (int i; tmp; i++) {
		out[i] = tmp[DATA];
		tmp = tmp[NEXT];
	    }

	    return out;
	}

	return UNDEFINED;
    }
}