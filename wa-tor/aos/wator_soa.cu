#define NDEBUG

#include <chrono>
#include <stdio.h>
#include <assert.h>
#include <inttypes.h>

#include "wa-tor/aos/wator_soa.h"

#define SPAWN_THRESHOLD 4
#define ENERGY_BOOST 4
#define ENERGY_START 2
//#define GRID_SIZE_X 400
//#define GRID_SIZE_Y 300

#define OPTION_SHARK_DIE true
#define OPTION_SHARK_SPAWN true
#define OPTION_FISH_SPAWN true

#define THREADS_PER_BLOCK 256
#define NUM_BLOCKS 1024

namespace wa_tor {

__device__ SoaAllocator<64*64*64*64, Agent, Fish, Shark, Cell> memory_allocator;

template<typename T, typename... Args>
__device__ T* allocate(Args... args) {
  return memory_allocator.make_new<T>(args...);
}

template<typename T>
__device__ void deallocate(T* ptr) {
  memory_allocator.free<T>(ptr);
}

  template<int TypeIndex>
  __device__ void deallocate_untyped(void* ptr) {
    memory_allocator.free_untyped<TypeIndex>(ptr);
  }

__device__ void initialize_allocator() {
  memory_allocator.initialize();
}

__device__ uint32_t random_number(uint32_t* state, uint32_t max) {
  // Advance and return random state.
  // Source: https://en.wikipedia.org/wiki/Lehmer_random_number_generator
  assert(*state != 0);
  *state = static_cast<uint32_t>(
      static_cast<uint64_t>(*state) * 1103515245u + 12345) % 2147483648u;
  return ((*state) >> 7) % max;
}

__device__ uint32_t random_number(uint32_t* state) {
  // Advance and return random state.
  // Source: https://en.wikipedia.org/wiki/Lehmer_random_number_generator
  assert(*state != 0);
  *state = static_cast<uint32_t>(
      static_cast<uint64_t>(*state) * 1103515245u + 12345) % 2147483648u;
  return ((*state) >> 7);
}

__device__ Cell::Cell(uint32_t random_state) : random_state_(random_state),
                                               agent_(nullptr) {
  assert(random_state != 0);
  prepare();
}

__device__ Agent* Cell::agent() const {
  return agent_;
}

__device__ void Cell::decide() {
  // TODO: Not sure why manual type cast is necessary.
  if (arr_neighbor_request(4)) {
    // This cell has priority.
    agent_->set_new_position(this);
  } else {
    uint8_t candidates[4];
    uint8_t num_candidates = 0;

    for (int i = 0; i < 4; ++i) {
      if (arr_neighbor_request(i)) {
        candidates[num_candidates++] = i;
      }
    }

    if (num_candidates > 0) {
      uint32_t selected_index = random_number(&random_state_, num_candidates);
      arr_neighbors(candidates[selected_index])->agent()->set_new_position(this);
    }
  }
}

__device__ void Cell::enter(Agent* agent) {
  assert(agent_ == nullptr);

//#ifndef NDEBUG
//  // Ensure that no two agents are trying to enter this cell at the same time.
//  uint64_t old_val = atomicExch(reinterpret_cast<unsigned long long int*>(&agent_),
//                                reinterpret_cast<unsigned long long int>(agent));
//  assert(old_val == 0);
//#else
  agent_ = agent;
//#endif

  agent->set_position(this);
}

__device__ bool Cell::has_fish() const {
  // TODO: Not sure why typecast is necessary.
  return agent_ != nullptr && ((Agent*)agent_)->type_identifier() == Fish::kTypeId;
}

__device__ bool Cell::has_shark() const {
  // TODO: Not sure why typecast is necessary.
  return agent_ != nullptr && ((Agent*)agent_)->type_identifier() == Shark::kTypeId;
}

__device__ bool Cell::is_free() const {
  return agent_ == nullptr;
}

__device__ void Cell::leave() {
  assert(agent_ != nullptr);
  agent_ = nullptr;
}

__device__ void Cell::prepare() {
  for (int i = 0; i < 5; ++i) {
    arr_neighbor_request(i) = false;
  }
}

__device__ uint32_t* Cell::random_state() {
  return &random_state_;
}

__device__ void Cell::request_random_fish_neighbor() {
  if (!request_random_neighbor<&Cell::has_fish>(agent_->random_state())) {
    // No fish found. Look for free cell.
    if (!request_random_neighbor<&Cell::is_free>(agent_->random_state())) {
      arr_neighbor_request(4) = true;
    }
  }
}

__device__ void Cell::request_random_free_neighbor() {
  if (!request_random_neighbor<&Cell::is_free>(agent_->random_state())) {
    arr_neighbor_request(4) = true;
  }
}

template<bool(Cell::*predicate)() const>
__device__ bool Cell::request_random_neighbor(uint32_t* random_state) {
  uint8_t candidates[4];
  uint8_t num_candidates = 0;

  for (int i = 0; i < 4; ++i) {
    if ((arr_neighbors(i)->*predicate)()) {
      candidates[num_candidates++] = i;
    }
  }

  if (num_candidates == 0) {
    return false;
  } else {
    uint32_t selected_index = random_number(random_state, num_candidates);
    uint8_t selected = candidates[selected_index];
    uint8_t neighbor_index = (selected + 2) % 4;
    arr_neighbors(selected)->arr_neighbor_request(neighbor_index) = true;

    // Check correctness of neighbor calculation.
    assert(arr_neighbors(selected)->arr_neighbors(neighbor_index) == this);

    return true;
  }
}

__device__ void Cell::set_neighbors(Cell* left, Cell* top,
                                    Cell* right, Cell* bottom) {
  arr_neighbors(0) = left;
  arr_neighbors(1) = top;
  arr_neighbors(2) = right;
  arr_neighbors(3) = bottom;
}

__device__ Agent::Agent(uint32_t random_state, uint8_t type_identifier)
    : random_state_(random_state), type_identifier_(type_identifier) {
  assert(random_state != 0);
}

__device__ uint32_t* Agent::random_state() {
  return &random_state_;
}

__device__ void Agent::set_new_position(Cell* new_pos) {
  // Check for race condition. (This is not bullet proof.)
  assert(new_position_ == position_);

  new_position_ = new_pos;
}

__device__ Cell* Agent::position() const {
  return position_;
}

__device__ void Agent::set_position(Cell* cell) {
  position_ = cell;
}

// TODO: Verify that RTTI (dynamic_cast) does not work in device code.
__device__ uint8_t Agent::type_identifier() const {
  return type_identifier_;
}

__device__ Fish::Fish(uint32_t random_state)
    : Agent(random_state, kTypeId), 
      egg_timer_(random_state % SPAWN_THRESHOLD) {
  assert(random_state != 0);
}

__device__ void Fish::prepare() {
  assert(type_identifier() == kTypeId);
  egg_timer_++;
  // Fallback: Stay on current cell.
  new_position_ = position_;

  assert(position_ != nullptr);
  position_->request_random_free_neighbor();
}

__device__ void Fish::update() {
  assert(type_identifier() == kTypeId);
  Cell* old_position = position_;

  if (old_position != new_position_) {
    old_position->leave();
    new_position_->enter(this);

    if (OPTION_FISH_SPAWN && egg_timer_ > SPAWN_THRESHOLD) {
      uint32_t new_random_state = random_number(&random_state_) + 401;
      new_random_state = new_random_state != 0 ? new_random_state
                                               : random_state_;
      auto* new_fish = allocate<Fish>(new_random_state);
      assert(new_fish != nullptr);
      old_position->enter(new_fish);
      egg_timer_ = (uint32_t) 0;
    }
  }
}


__device__ Shark::Shark(uint32_t random_state)
    : Agent(random_state, kTypeId), energy_(ENERGY_START),
      egg_timer_(random_state % SPAWN_THRESHOLD) {
  assert(random_state_ != 0);
}

__device__ void Shark::prepare() {
  assert(type_identifier() == kTypeId);
  egg_timer_++;
  energy_--;

  assert(position_ != nullptr);
  if (OPTION_SHARK_DIE && energy_ == 0) {
    // Do nothing. Shark will die.
  } else {
    // Fallback: Stay on current cell.
    new_position_ = position_;
    position_->request_random_fish_neighbor();
  }
}

__device__ void Shark::update() {
  assert(type_identifier() == kTypeId);

  if (OPTION_SHARK_DIE && energy_ == 0) {
    position_->kill();
  } else {
    Cell* old_position = position_;

    if (old_position != new_position_) {
      if (new_position_->has_fish()) {
        energy_ += ENERGY_BOOST;
        new_position_->kill();
      }

      old_position->leave();
      new_position_->enter(this);

      if (OPTION_SHARK_SPAWN && egg_timer_ > SPAWN_THRESHOLD) {
        assert(random_state_ != 0);
        uint32_t new_random_state = random_number(&random_state_) + 601;
        new_random_state = new_random_state != 0 ? new_random_state
                                                 : random_state_;
        auto* new_shark = allocate<Shark>(new_random_state);
        assert(new_shark != nullptr);
        old_position->enter(new_shark);
        egg_timer_ = 0;
      }
    }
  }
}

__device__ void Cell::kill() {
  assert(agent_ != nullptr);
  if (agent_->type_identifier() == 1) {
    deallocate_untyped<1>(agent_);
  } else if (agent_->type_identifier() == 2) {
    deallocate_untyped<2>(agent_);
  } else {
    // Unknown type.
    assert(false);
  }
  agent_ = nullptr;
}


// ----- KERNELS -----

__device__ Cell* cells[GRID_SIZE_X * GRID_SIZE_Y];

__global__ void create_cells() {
  int tid = threadIdx.x + blockDim.x*blockIdx.x;

  if (tid < GRID_SIZE_Y*GRID_SIZE_X) {
    int x = tid % GRID_SIZE_X;
    int y = tid / GRID_SIZE_X;

    float init_state = __logf(tid + 401);
    uint32_t init_state_int = *reinterpret_cast<uint32_t*>(&init_state);

    // Cell* new_cell = new Cell(init_state_int);
    Cell* new_cell = allocate<Cell>(601*x*x*y + init_state_int);
    assert(new_cell != nullptr);
    cells[tid] = new_cell;
  }
}

__global__ void setup_cells() {
  int tid = threadIdx.x + blockDim.x*blockIdx.x;

  if (tid < GRID_SIZE_Y*GRID_SIZE_X) {
    int x = tid % GRID_SIZE_X;
    int y = tid / GRID_SIZE_X;

    Cell* left = x > 0 ? cells[y*GRID_SIZE_X + x - 1]
                       : cells[y*GRID_SIZE_X + GRID_SIZE_X - 1];
    Cell* right = x < GRID_SIZE_X - 1 ? cells[y*GRID_SIZE_X + x + 1]
                                      : cells[y*GRID_SIZE_X];
    Cell* top = y > 0 ? cells[(y - 1)*GRID_SIZE_X + x]
                      : cells[(GRID_SIZE_Y - 1)*GRID_SIZE_X + x];
    Cell* bottom = y < GRID_SIZE_Y - 1 ? cells[(y + 1)*GRID_SIZE_X + x]
                                       : cells[x];

    // left, top, right, bottom
    cells[tid]->set_neighbors(left, top, right, bottom);

    // Initialize with random agent.
    uint32_t agent_type = random_number(cells[tid]->random_state(), 4);
    if (agent_type == 0) {
      auto* agent = allocate<Fish>(*(cells[tid]->random_state()));
      assert(agent != nullptr);
      cells[tid]->enter(agent);
    } else if (agent_type == 1) {
      auto* agent = allocate<Shark>(*(cells[tid]->random_state()));
      assert(agent != nullptr);
      cells[tid]->enter(agent);
    } else {
      // Free cell.
    }
  }
}

// Problem: It is not easy to keep track of all objects of a class if they are
// dynamically allocated. But we want to benchmark the performance of new/
// delete in CUDA.
// Solution: Fill these arrays in a separate kernel by iterating over all
// cells, storing agents in the respective array slots, and compacting the
// arrays. We do not measure the performance of these steps.
__device__ uint32_t num_sharks = 0;
__device__ Shark* sharks[GRID_SIZE_Y * GRID_SIZE_X];
__device__ uint32_t num_fish = 0;
__device__ Fish*  fish[GRID_SIZE_Y * GRID_SIZE_X];

__global__ void print_checksum() {
  uint64_t chksum = 0;

  // Sorting of the array does not matter in the calculation here.
  for (int i = 0; i < num_sharks; ++i) {
    chksum += *(sharks[i]->position()->random_state()) % 601;
  }

  for (int i = 0; i < num_fish; ++i) {
    chksum += *(fish[i]->position()->random_state()) % 601;
  }

  uint32_t fish_use = memory_allocator.DBG_used_slots<Fish>();
  uint32_t fish_num = memory_allocator.DBG_allocated_slots<Fish>();
  uint32_t shark_use = memory_allocator.DBG_used_slots<Shark>();
  uint32_t shark_num = memory_allocator.DBG_allocated_slots<Shark>();

  printf("%" PRIu64, chksum);
  printf(",%u,%u,%u,%u,%i\n",
         fish_use, fish_num, shark_use, shark_num, (int) GRID_SIZE_X*GRID_SIZE_Y);
}

__global__ void reset_fish_array() {
  num_fish = 0;
}

__global__ void reset_shark_array() {
  num_sharks = 0;
}

// One thread per cell.
__global__ void find_fish() {
  int tid = threadIdx.x + blockDim.x*blockIdx.x;

  if (tid < GRID_SIZE_Y*GRID_SIZE_X) {
    if (cells[tid]->has_fish()) {
      uint32_t idx = atomicAdd(&num_fish, 1);
      fish[idx] = reinterpret_cast<Fish*>(cells[tid]->agent());
    }
  }
}

// One thread per cell.
__global__ void find_sharks() {
  int tid = threadIdx.x + blockDim.x*blockIdx.x;

  if (tid < GRID_SIZE_Y*GRID_SIZE_X) {
    if (cells[tid]->has_shark()) {
      uint32_t idx = atomicAdd(&num_sharks, 1);
      sharks[idx] = reinterpret_cast<Shark*>(cells[tid]->agent());
    }
  }
}

__global__ void find_fish_soa() {
  assert(gridDim.x * blockDim.x == 1);
  num_fish = 0;
  for (int i = 0; i < decltype(memory_allocator)::kN; ++i) {
    if (memory_allocator.is_block_allocated<Fish>(i)) {
      auto* block = memory_allocator.get_block<Fish>(i);
      for (int j = 0; j < Fish::kBlockSize; ++j) {
        if (block->is_slot_allocated(j)) {
          fish[num_fish++] = block->make_pointer(j);
        }
      }
    }
  }
}

__global__ void find_sharks_soa() {
  assert(gridDim.x * blockDim.x == 1);
  num_sharks = 0;
  for (int i = 0; i < decltype(memory_allocator)::kN; ++i) {
    if (memory_allocator.is_block_allocated<Shark>(i)) {
      auto* block = memory_allocator.get_block<Shark>(i);
      for (int j = 0; j < Shark::kBlockSize; ++j) {
        if (block->is_slot_allocated(j)) {
          sharks[num_sharks++] = block->make_pointer(j);
        }
      }
    }
  }
}

__global__ void find_cells_soa() {
  assert(gridDim.x * blockDim.x == 1);
  uint32_t num_cells = 0;
  for (int i = 0; i < decltype(memory_allocator)::kN; ++i) {
    if (memory_allocator.is_block_allocated<Cell>(i)) {
      auto* block = memory_allocator.get_block<Cell>(i);
      for (int j = 0; j < Cell::kBlockSize; ++j) {
        if (block->is_slot_allocated(j)) {
          cells[num_cells++] = block->make_pointer(j);
        }
      }
    }
  }
}

void generate_fish_array_soa() {
  find_fish_soa<<<1,1>>>();
  gpuErrchk(cudaDeviceSynchronize());
}

void generate_shark_array_soa() {
  find_sharks_soa<<<1,1>>>();
  gpuErrchk(cudaDeviceSynchronize());
}

void generate_fish_array_no_soa() {
  reset_fish_array<<<1, 1>>>();
  gpuErrchk(cudaDeviceSynchronize());
  find_fish<<<GRID_SIZE_X*GRID_SIZE_Y/1024 + 1, 1024>>>();
  gpuErrchk(cudaDeviceSynchronize());
}

void generate_shark_array_no_soa() {
  reset_shark_array<<<1, 1>>>();
  gpuErrchk(cudaDeviceSynchronize());
  find_sharks<<<GRID_SIZE_X*GRID_SIZE_Y/1024 + 1, 1024>>>();
  gpuErrchk(cudaDeviceSynchronize());
}

void generate_fish_array() {
  generate_fish_array_soa();
}

void generate_shark_array() {
  generate_shark_array_soa();
}


__global__ void cell_prepare() {
  for (int tid = threadIdx.x + blockDim.x*blockIdx.x;
       tid < GRID_SIZE_Y*GRID_SIZE_X;
       tid += blockDim.x*gridDim.x) {
    cells[tid]->prepare();
  }
}

__global__ void cell_decide() {
  for (int tid = threadIdx.x + blockDim.x*blockIdx.x;
       tid < GRID_SIZE_Y*GRID_SIZE_X;
       tid += blockDim.x*gridDim.x) {
    cells[tid]->decide();
  }
}

__global__ void fish_prepare() {
  for (int tid = threadIdx.x + blockDim.x*blockIdx.x;
       tid < num_fish;
       tid += blockDim.x*gridDim.x) {
    assert(fish[tid] != nullptr);
    fish[tid]->prepare();
  }
}

__global__ void fish_update() {
  for (int tid = threadIdx.x + blockDim.x*blockIdx.x;
       tid < num_fish;
       tid += blockDim.x*gridDim.x) {
    assert(fish[tid] != nullptr);
    fish[tid]->update();
  }
}

__global__ void shark_prepare() {
  for (int tid = threadIdx.x + blockDim.x*blockIdx.x;
       tid < num_sharks;
       tid += blockDim.x*gridDim.x) {
    assert(sharks[tid] != nullptr);
    sharks[tid]->prepare();
  }
}

__global__ void shark_update() {
  for (int tid = threadIdx.x + blockDim.x*blockIdx.x;
       tid < num_sharks;
       tid += blockDim.x*gridDim.x) {
    assert(sharks[tid] != nullptr);
    sharks[tid]->update();
  }
}

void generate_shark_fish_arrays() {
  generate_fish_array();
  generate_shark_array();
}

void step() {
  cell_prepare<<<NUM_BLOCKS, THREADS_PER_BLOCK>>>();
  gpuErrchk(cudaDeviceSynchronize());
  fish_prepare<<<NUM_BLOCKS, THREADS_PER_BLOCK>>>();
  gpuErrchk(cudaDeviceSynchronize());
  cell_decide<<<NUM_BLOCKS, THREADS_PER_BLOCK>>>();
  gpuErrchk(cudaDeviceSynchronize());
  fish_update<<<NUM_BLOCKS, THREADS_PER_BLOCK>>>();
  gpuErrchk(cudaDeviceSynchronize());

  cell_prepare<<<NUM_BLOCKS, THREADS_PER_BLOCK>>>();
  gpuErrchk(cudaDeviceSynchronize());
  shark_prepare<<<NUM_BLOCKS, THREADS_PER_BLOCK>>>();
  gpuErrchk(cudaDeviceSynchronize());
  cell_decide<<<NUM_BLOCKS, THREADS_PER_BLOCK>>>();
  gpuErrchk(cudaDeviceSynchronize());
  shark_update<<<NUM_BLOCKS, THREADS_PER_BLOCK>>>();
  gpuErrchk(cudaDeviceSynchronize());
}

__global__ void init_memory_system() {
  initialize_allocator();
}

void initialize() {
  init_memory_system<<<GRID_SIZE_X*GRID_SIZE_Y/1024 + 1, 1024>>>();
  gpuErrchk(cudaDeviceSynchronize());

  create_cells<<<GRID_SIZE_X*GRID_SIZE_Y/1024 + 1, 1024>>>();
  gpuErrchk(cudaDeviceSynchronize());
  setup_cells<<<GRID_SIZE_X*GRID_SIZE_Y/1024 + 1, 1024>>>();
  gpuErrchk(cudaDeviceSynchronize());
}

__device__ uint32_t d_gui_map[GRID_SIZE_Y * GRID_SIZE_X];
uint32_t gui_map[GRID_SIZE_Y * GRID_SIZE_X];

__global__ void fill_gui_map() {
  int tid = threadIdx.x + blockDim.x*blockIdx.x;

  if (tid < GRID_SIZE_Y*GRID_SIZE_X) {
    if (cells[tid]->agent() != nullptr) {
      d_gui_map[tid] = cells[tid]->agent()->type_identifier();
    } else {
      d_gui_map[tid] = 0;
    }
  }
}

void update_gui_map() {
  fill_gui_map<<<GRID_SIZE_X*GRID_SIZE_Y/1024 + 1, 1024>>>();
  gpuErrchk(cudaDeviceSynchronize());

  cudaMemcpyFromSymbol(gui_map, d_gui_map, sizeof(uint32_t)*GRID_SIZE_X*GRID_SIZE_Y,
                       0, cudaMemcpyDeviceToHost);
  gpuErrchk(cudaDeviceSynchronize());
}


int h_num_fish = 0;
int h_num_sharks = 0;


void print_stats() {
  generate_fish_array();
  generate_shark_array();
  //printf("FISH: %i,SHARKS: %i,", h_num_fish, h_num_sharks);
  print_checksum<<<1, 1>>>();
  gpuErrchk(cudaDeviceSynchronize());
}

int main(int argc, char* arvg[]) {
  cudaDeviceSetLimit(cudaLimitMallocHeapSize, 256*1024*1024);

  size_t heap_size;
  cudaDeviceGetLimit(&heap_size, cudaLimitMallocHeapSize);
  //printf("CUDA heap size: %lu\n", heap_size);

  initialize();

  // To ensure cells are accessed properly (SOA).
  find_cells_soa<<<1, 1>>>();
  gpuErrchk(cudaDeviceSynchronize());

  //printf("Computing...");
  int total_time = 0;
  for (int i = 0; i < 100; ++i) {
    if (i%50==0) {
      //render();
    }

    generate_shark_fish_arrays();

    // Printing: RUNNING TIME, NUM_FISH, NUM_SHARKS, CHKSUM, FISH_USE, FISH_ALLOC, SHARK_USE, SHARK_ALLOC
    auto time_before = std::chrono::system_clock::now();
    step();
    auto time_after = std::chrono::system_clock::now();
    int time_running = std::chrono::duration_cast<std::chrono::microseconds>(
        time_after - time_before).count();
    total_time += time_running;
  }
  printf("%i,", total_time);
  print_stats();

  return 0;
}

}  // namespace wa_tor

int main(int argc, char* arvg[]) {
  return wa_tor::main(0, nullptr);
}
