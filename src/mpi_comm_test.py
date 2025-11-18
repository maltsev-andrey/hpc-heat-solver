from mpi4py import MPI
import numpy as np

comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()

# Test communication
data_size = 1000000  # 1M floats
send_data = np.ones(data_size, dtype=np.float64) * rank
recv_data = np.empty(data_size, dtype=np.float64)

start = MPI.Wtime()
next_rank = (rank + 1) % size
prev_rank = (rank - 1) % size

# Fixed syntax - separate buffers for send and receive
comm.Sendrecv(sendbuf=send_data, dest=next_rank, recvbuf=recv_data, source=prev_rank)
end = MPI.Wtime()

if rank == 0:
    bandwidth = (data_size * 8) / (end - start) / 1e6  # MB/s
    print(f"Communication test: {end-start:.3f} sec, {bandwidth:.1f} MB/s")
    print(f"Received data from rank {prev_rank}: first element = {recv_data[0]}")
