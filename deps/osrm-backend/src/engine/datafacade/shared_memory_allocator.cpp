#include "engine/datafacade/shared_memory_allocator.hpp"
#include <vector>

namespace osrm
{
namespace engine
{
namespace datafacade
{

// 1. 完美咬合官方 ShmKey vector 參數簽名
SharedMemoryAllocator::SharedMemoryAllocator(const std::vector<storage::SharedRegionRegister::ShmKey> &) {}

SharedMemoryAllocator::~SharedMemoryAllocator() {}

// 2. 完美咬合官方 const 傳回值簽名
const storage::SharedDataIndex &SharedMemoryAllocator::GetIndex()
{
    static storage::SharedDataIndex dummy;
    return dummy;
}

} // namespace datafacade
} // namespace engine
} // namespace osrm
