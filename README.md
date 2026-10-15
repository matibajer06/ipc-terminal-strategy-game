\# Multi-Process Terminal RTS Engine (C / System V IPC)



An authoritative multiplayer real-time strategy engine designed for POSIX-compliant Linux environments, written in pure C. 



The project executes across multiple decoupled operating system processes, showcasing low-level concurrency control, inter-process communication (IPC) via System V primitives (shared memory, message queues, counting semaphores), deterministic tick-based simulation, and robust kernel resource lifecycle management.



\## System Architecture



The engine adopts an authoritative server pattern. Clients maintain zero local gameplay authority; they act purely as visual terminals and asynchronous command dispatchers.



```text

&#x20;              +-------------------------------------------------+

&#x20;              |             Game State in Shared Memory         |

&#x20;              |                     (Key: 2001)                 |

&#x20;              |  - Active Game Flag                             |

&#x20;              |  - Player A State (Gold, Army, Queue, VP)       |

&#x20;              |  - Player B State (Gold, Army, Queue, VP)       |

&#x20;              |  - Active Attack Payload                        |

&#x20;              +-----------------------+-------------------------+

&#x20;                                      ^

&#x20;                                      | Protected by Semaphore (SEM\_ID)

&#x20;                                      v

&#x20;                    +-----------------------------------+

&#x20;                    |       Authoritative Server        |

&#x20;                    |             (server.c)            |

&#x20;                    |  - Fixed 1-Second Tick Loop       |

&#x20;                    |  - Economic Accretion Engine      |

&#x20;                    |  - Unit Production Pipeline       |

&#x20;                    |  - Combat \& Resolution Matrix     |

&#x20;                    |  - Signal Trap (SIGINT Cleanup)   |

&#x20;                    +---------+---------------+---------+

&#x20;                              |               |

&#x20;           MSG\_UPDATE (3002)  |               |  MSG\_UPDATE (3002)

&#x20;           (State Broadcast)  |               |  (State Broadcast)

&#x20;                              v               v

&#x20;               +------------------+       +------------------+

&#x20;               | Message Queue A  |       | Message Queue B  |

&#x20;               |    (Key: 1001)   |       |    (Key: 1002)   |

&#x20;               +--------+---------+       +---------+--------+

&#x20;                        ^                           ^

&#x20;       MSG\_ORDER (3001) |                           | MSG\_ORDER (3001)

&#x20;       (Commands: Train/Attack)                     | (Commands: Train/Attack)

&#x20;                        |                           |

&#x20;            +-----------+--------+         +--------+-----------+

&#x20;            |   Client: Player A |         |   Client: Player B |

&#x20;            |      (client.c)    |         |      (client.c)    |

&#x20;            |  - Terminal UI     |         |  - Terminal UI     |

&#x20;            |  - Action Dispatch |         |  - Action Dispatch |

&#x20;            +--------------------+         +--------------------+

```



\## Low-Level IPC Implementation



\### 1. Shared Memory Segment (`SHM\_ID = 2001`)

Allocates a shared virtual memory page accessed concurrently by the server runtime and detached background routines via `shmget()` and `shmat()`.



```c

typedef struct {

&#x20;   int game\_active;             // Global simulation state flag

&#x20;   Player player\_A;             // Player A: Gold, Army stats, Training queue, VP

&#x20;   Player player\_B;             // Player B: Gold, Army stats, Training queue, VP

&#x20;   Attack current\_attack;       // Active assault payload (attacker ID, composition, countdown)

} Game;

```



\### 2. Synchronization \& Critical Sections (`SEM\_ID`)

State mutations inside shared memory (economic calculation, production countdowns, and combat resolution) are encapsulated within binary/counting semaphore locks using `semop()`.

\- \*\*Race Condition Prevention:\*\* Eliminates torn reads and write-write hazards between async client order dispatchers and the periodic server simulation tick.

\- \*\*Deadlock Avoidance:\*\* Strict lock-acquisition hierarchy with zero nested locking.



\### 3. Bidirectional Message Queues (`ID\_QUEUE\_A = 1001`, `ID\_QUEUE\_B = 1002`)

Dedicated kernel message channels utilizing `msgsnd()` and `msgrcv()` for asynchronous order routing and synchronous screen refreshes.



```c

typedef struct {

&#x20;   long mtype;                  // 3001: MSG\_ORDER | 3002: MSG\_UPDATE

&#x20;   int action;                  // Action opcode: TRAIN (1), ATTACK (2)

&#x20;   int unit\_type;               // Unit classification ID \[0 - 3]

&#x20;   int count;                   // Quantity to enqueue

&#x20;   int army\[3];                 // Attack deployment payload: \[Light, Heavy, Cavalry]

&#x20;   Player current\_state;        // Serialized state snapshot sent during tick updates

} MessageBuff;

```



\## Protocol \& Event Flow



| Channel ID | Type Envelope | Direction | Identifier | Payload / Description |

| :--- | :--- | :--- | :--- | :--- |

| `1001` / `1002` | `MSG\_ORDER` | Client -> Server | `3001` | Non-blocking command packet. Contains target opcode (`TRAIN` or `ATTACK`), unit indexes, and quantity arrays. |

| `1001` / `1002` | `MSG\_UPDATE` | Server -> Client | `3002` | Fixed-frequency state broadcast. Transmits serialized `Player` struct containing current gold, units, and active queue to redraw terminal UI. |

| `2001` | `Shared Memory` | Mapped | N/A | Persistent game world state mutated solely by the server under semaphore protection. |



\### Lifecycle \& Graceful Teardown

To prevent orphaned kernel allocations in System V tables, the server traps `SIGINT` (`Ctrl+C`):

\- Destroys shared memory segment: `shmctl(shm\_id, IPC\_RMID, NULL)`

\- Destroys inbound/outbound queues: `msgctl(queue\_a, IPC\_RMID, NULL)`, `msgctl(queue\_b, IPC\_RMID, NULL)`

\- Destroys synchronization sets: `semctl(sem\_id, 0, IPC\_RMID)`



\## Repository Structure



```text

.

├── client.c        # Client entrypoint, non-blocking input parsing \& ANSI UI

├── server.c        # Authoritative game engine, tick simulation \& IPC orchestrator

├── structures.h    # Shared protocol definitions, constants, and packet layouts

├── Makefile        # Compilation recipe with optimization \& strict warning flags

├── .gitignore      # Build artifact exclusion rules

└── README.md

```



\## Build \& Setup



\### Prerequisites

\- Linux OS (Ubuntu 20.04+, Debian, Fedora, Arch) with System V IPC enabled

\- GCC or Clang compiler

\- GNU Make



\### 1. Build Executables

Run the compilation pipeline:

```bash

make

```



To clean object files and binaries:

```bash

make clean

```



\### 2. Launching the Multi-Process Cluster

Open three distinct terminal windows and execute the commands in the following sequence:



```bash

\# Terminal 1: Spin up the authoritative engine

./server



\# Terminal 2: Connect Player A

./client A



\# Terminal 3: Connect Player B

./client B

```



\## Debugging \& IPC Inspection



To verify kernel resource allocation while the simulation is running, inspect the active System V IPC tables:



```bash

\# View active shared memory, message queues, and semaphores

ipcs



\# View detailed queue status

ipcs -q



\# Manually purge orphaned segments if abnormal termination occurs

ipcrm -M 2001

ipcrm -Q 1001

ipcrm -Q 1002

```



\## Game Rules \& Victory Conditions



\- \*\*Resource Tick:\*\* Players automatically accrue gold each second.

\- \*\*Unit Production:\*\* Gold can be queued to train light units, heavy infantry, or cavalry.

\- \*\*Combat Mechanics:\*\* Strategic unit counter mechanics calculate offensive losses and defensive casualties.

\- \*\*Victory Condition:\*\* First player to achieve 5 Victory Points (VP) wins the match, triggering clean engine termination.

