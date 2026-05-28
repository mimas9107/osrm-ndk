#include "storage/storage.hpp"
#include <vector>
#include <string>
#include <utility>

namespace osrm { namespace storage {

Storage::Storage(StorageConfig) {}

std::vector<std::pair<bool, boost::filesystem::path>> Storage::GetStaticFiles() { 
    return std::vector<std::pair<bool, boost::filesystem::path>>(); 
}

std::vector<std::pair<bool, boost::filesystem::path>> Storage::GetUpdatableFiles() { 
    return std::vector<std::pair<bool, boost::filesystem::path>>(); 
}

std::string Storage::PopulateLayoutWithRTree(storage::BaseDataLayout &) { 
    return std::string(); 
}

void Storage::PopulateLayout(storage::BaseDataLayout &, const std::vector<std::pair<bool, boost::filesystem::path>> &) {}

void Storage::PopulateStaticData(const SharedDataIndex &) {}

void Storage::PopulateUpdatableData(const SharedDataIndex &) {}

void populateLayoutFromFile(boost::filesystem::path const&, BaseDataLayout&) {}

}}
