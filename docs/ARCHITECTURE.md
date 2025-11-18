# HPC Cluster Architecture

This document provides visual diagrams of the cluster architecture and solver workflow.

## Network Topology

```mermaid
graph TB
    subgraph External["External Network (170.168.1.0/24)"]
        User[User Workstation]
        Internet[Internet]
    end
    
    subgraph HeadNode["Head Node (srv-hpc-01)"]
        SSH[SSH Gateway]
        NFS[NFS Server<br/>400GB XFS]
        Scheduler[Job Scheduler]
    end
    
    subgraph Internal["Internal Cluster Network (10.10.10.0/24)"]
        direction LR
        CN1[srv-hpc-02<br/>6 cores]
        CN2[srv-hpc-03<br/>6 cores]
        CN3[srv-hpc-04<br/>6 cores]
        CN4[srv-hpc-05<br/>6 cores]
    end
    
    User -->|SSH| SSH
    Internet -->|Updates/Packages| HeadNode
    SSH -->|Jump Host| Internal
    NFS -->|Shared Storage| Internal
    Scheduler -->|MPI Launch| Internal
    
    style HeadNode fill:#e1f5ff
    style Internal fill:#fff4e1
    style External fill:#f0f0f0
```

## MPI Domain Decomposition

```mermaid
graph LR
    subgraph GlobalGrid["Global Grid (1024×1024)"]
        direction TB
        P0[Process 0<br/>Rows 0-42]
        P1[Process 1<br/>Rows 43-85]
        P2[Process 2<br/>Rows 86-128]
        Pdots[...]
        P23[Process 23<br/>Rows 981-1023]
    end
    
    subgraph Nodes["Compute Nodes"]
        direction TB
        N1[srv-hpc-02<br/>Processes 0-5]
        N2[srv-hpc-03<br/>Processes 6-11]
        N3[srv-hpc-04<br/>Processes 12-17]
        N4[srv-hpc-05<br/>Processes 18-23]
    end
    
    P0 -.->|Ghost Cell<br/>Exchange| P1
    P1 -.->|Ghost Cell<br/>Exchange| P2
    P2 -.->|Ghost Cell<br/>Exchange| Pdots
    Pdots -.->|Ghost Cell<br/>Exchange| P23
    
    N1 ---|MPI Comm| N2
    N2 ---|MPI Comm| N3
    N3 ---|MPI Comm| N4
    
    style GlobalGrid fill:#e8f5e9
    style Nodes fill:#fff3e0
```

## Solver Workflow

```mermaid
flowchart TD
    Start([Start MPI Job]) --> Init[Initialize MPI<br/>rank, size]
    Init --> Parse[Parse Arguments<br/>nx, ny, steps]
    Parse --> Decompose[Domain Decomposition<br/>Split along x-axis]
    
    Decompose --> Alloc[Allocate Arrays<br/>u, u_new with ghost cells]
    Alloc --> InitCond[Set Initial Condition<br/>Hot spot at center]
    
    InitCond --> TimeLoop{More time<br/>steps?}
    
    TimeLoop -->|Yes| Exchange[Exchange Ghost Cells<br/>MPI Send/Recv]
    Exchange --> Compute[Compute Laplacian<br/>Update interior points]
    Compute --> Boundary[Apply Boundary<br/>Conditions]
    Boundary --> Swap[Swap Arrays<br/>u ↔ u_new]
    Swap --> Progress[Report Progress<br/>Rank 0 only]
    Progress --> TimeLoop
    
    TimeLoop -->|No| Gather[Gather Center<br/>Temperature]
    Gather --> Stats[Calculate Performance<br/>Statistics]
    Stats --> Output[Output Results<br/>Rank 0 only]
    Output --> End([End MPI Job])
    
    style Start fill:#c8e6c9
    style End fill:#ffcdd2
    style Exchange fill:#fff9c4
    style Compute fill:#b3e5fc
```

## Data Flow Between Processes

```mermaid
sequenceDiagram
    participant P0 as Process 0
    participant P1 as Process 1
    participant P2 as Process 2
    participant PN as Process N-1
    
    Note over P0,PN: Time Step Begins
    
    par Ghost Cell Exchange
        P0->>P1: Send bottom boundary
        P1->>P0: Send top boundary
        P1->>P2: Send bottom boundary
        P2->>P1: Send top boundary
        P2->>PN: Send bottom boundary
        PN->>P2: Send top boundary
    end
    
    Note over P0,PN: All processes compute<br/>local updates
    
    par Local Computation
        P0->>P0: Update interior points
        P1->>P1: Update interior points
        P2->>P2: Update interior points
        PN->>PN: Update interior points
    end
    
    Note over P0,PN: Apply boundary conditions
    
    Note over P0,PN: Time Step Complete
```

## Performance Scaling

```mermaid
graph LR
    subgraph WeakScaling["Weak Scaling Performance"]
        direction TB
        B1[1024² Grid<br/>8.73M updates/sec<br/>100% efficiency]
        B2[2048² Grid<br/>8.35M updates/sec<br/>95.6% efficiency]
        B3[4096² Grid<br/>8.25M updates/sec<br/>94.5% efficiency]
        
        B1 --> B2
        B2 --> B3
    end
    
    style B1 fill:#c8e6c9
    style B2 fill:#fff9c4
    style B3 fill:#ffccbc
```

## Storage Architecture

```mermaid
graph TB
    subgraph HeadNode["srv-hpc-01 (Head Node)"]
        Local[Local Disk<br/>System Files]
        NFSServer[NFS Server<br/>400GB XFS<br/>/nfs/shared]
    end
    
    subgraph Project["Heat Equation Project"]
        Source[src/<br/>Python solver]
        Scripts[scripts/<br/>Benchmarks]
        Config[config/<br/>Hostfiles]
        Results[benchmark_results/<br/>Output data]
    end
    
    subgraph ComputeNodes["Compute Nodes"]
        CN1[srv-hpc-02]
        CN2[srv-hpc-03]
        CN3[srv-hpc-04]
        CN4[srv-hpc-05]
    end
    
    Local -->|Stores| NFSServer
    NFSServer -->|Exports| Project
    Project -->|NFS Mount| CN1
    Project -->|NFS Mount| CN2
    Project -->|NFS Mount| CN3
    Project -->|NFS Mount| CN4
    
    style NFSServer fill:#e1f5ff
    style Project fill:#f3e5f5
    style ComputeNodes fill:#fff3e0
```

## Heat Equation Visualization

```mermaid
graph TB
    subgraph Physics["Physical Problem"]
        Heat[2D Heat Diffusion<br/>∂u/∂t = α∇²u]
        IC[Initial: Hot spot at center]
        BC[Boundary: Fixed at 0°C]
    end
    
    subgraph Numerical["Numerical Method"]
        FD[Finite Difference<br/>FTCS Scheme]
        CFL[CFL Stability<br/>dt ≤ 0.25·dx²/α]
        Ghost[Ghost Cells<br/>for MPI boundaries]
    end
    
    subgraph Parallel["Parallel Implementation"]
        MPI[MPI Processes<br/>24 total]
        Decomp[1D Decomposition<br/>Along x-axis]
        Comm[Point-to-Point<br/>Communication]
    end
    
    Heat --> FD
    IC --> FD
    BC --> FD
    FD --> CFL
    FD --> Ghost
    Ghost --> MPI
    MPI --> Decomp
    Decomp --> Comm
    
    style Physics fill:#e8f5e9
    style Numerical fill:#fff3e0
    style Parallel fill:#e1f5ff
```

## Technology Stack

```mermaid
graph TB
    subgraph Application["Application Layer"]
        Solver[Heat Equation Solver<br/>Python + NumPy]
        Bench[Benchmark Suite<br/>Bash Scripts]
    end
    
    subgraph Middleware["Middleware Layer"]
        MPI4Py[mpi4py<br/>Python MPI Bindings]
        OpenMPI[OpenMPI 4.1.x<br/>Message Passing]
    end
    
    subgraph System["System Layer"]
        RHEL[RHEL 9.5<br/>Operating System]
        Network[10Gbps Network<br/>Internal Cluster]
        Storage[NFS/XFS<br/>Shared Storage]
    end
    
    subgraph Hardware["Hardware Layer"]
        CPU[24 CPU Cores<br/>x86_64]
        RAM[30GB RAM<br/>Distributed]
        Disk[400GB Storage]
    end
    
    Solver --> MPI4Py
    Bench --> OpenMPI
    MPI4Py --> OpenMPI
    OpenMPI --> RHEL
    RHEL --> Network
    RHEL --> Storage
    Network --> Hardware
    Storage --> Disk
    RHEL --> CPU
    RHEL --> RAM
    
    style Application fill:#c8e6c9
    style Middleware fill:#fff9c4
    style System fill:#b3e5fc
    style Hardware fill:#ffccbc
```

---

These diagrams provide a comprehensive visual overview of the HPC cluster architecture, data flow, and solver implementation. For interactive versions, paste the Mermaid code into [Mermaid Live Editor](https://mermaid.live/).
