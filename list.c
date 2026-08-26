/*
 * list.c - Implementation of the linked list of owned strings.
 * See list.h for the public API.
 */
#include "list.h"

#include "logging.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/**
 * Allocate a new node (data + string) on the heap.
 * Exits the process on allocation failure (fatal error).
 */
Node *list_new_node(const char *str)
{
    Node *new_node = malloc(sizeof(Node));
    if (!new_node) {
        LOG_ERROR("Cannot allocate node.");
        exit(EXIT_FAILURE);
    }

    new_node->data = malloc(strlen(str) + 1);
    if (!new_node->data) {
        LOG_ERROR("Cannot allocate node data for \"%s\".", str);
        free(new_node);
        exit(EXIT_FAILURE);
    }
    strcpy(new_node->data, str);
    new_node->next = NULL;

    return new_node;
}

/**
 * Append a new string node to the tail of the list, updating
 * *head / *tail as needed.
 */
void list_append(Node **head, Node **tail, const char *str)
{
    Node *new_node = list_new_node(str);

    if (*head == NULL) {
        *head = new_node;
        *tail = new_node;
    } else {
        (*tail)->next = new_node;
        *tail         = new_node;
    }

    LOG_DEBUG("Appended \"%s\" to list.", str);
}

/** Free every node and the string it owns. */
void free_list(Node *head)
{
    Node *next;

    while (head != NULL) {
        next = head->next;
        free(head->data);
        free(head);
        head = next;
    }

    LOG_DEBUG("Freed all list nodes.");
}