/* ------------------------------------------------------------------
 * list.h - Singly linked list of owned strings
 *
 * Each Node owns a heap-allocated copy of its string (Node::data).
 * The list is managed by head/tail pointers passed in by the caller
 * (dependency inversion: no global list state).
 * ------------------------------------------------------------------ */
#ifndef LIST_H
#define LIST_H

typedef struct Node {
    char         *data;
    struct Node  *next;
} Node;

/**
 * Allocate a new node (data + string) on the heap.
 * Exits the process on allocation failure (fatal error).
 */
Node *list_new_node(const char *str);

/**
 * Append a new string node to the tail of the list, updating
 * *head / *tail as needed.
 */
void list_append(Node **head, Node **tail, const char *str);

/** Free every node and the string it owns. */
void free_list(Node *head);

#endif /* LIST_H */