CC = gcc
CFLAGS = -Wall

all: server client

server: server.c structures.h
	$(CC) $(CFLAGS) -o server server.c

client: client.c structures.h
	$(CC) $(CFLAGS) -o client client.c

clean:
	rm -f server client
