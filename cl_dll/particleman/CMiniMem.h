#pragma once

#include <algorithm>
#include <cstddef>
#include <vector>

class CBaseParticle;

#define TRIANGLE_FPS 30

// Minimal stand-in for std::pmr::unsynchronized_pool_resource: the glibc-2.28 buildchain's
// gcc-8.3 has no <memory_resource>. Same allocate/deallocate/release surface CMiniMem uses,
// backed by ::operator new (max_align_t-aligned, which satisfies CBaseParticle). release()
// frees everything still outstanding.
class CMiniPool
{
private:
	std::vector<void*> _blocks;

public:
	void* allocate(std::size_t sizeInBytes, std::size_t /*alignment*/ = 0)
	{
		void* p = ::operator new(sizeInBytes);
		_blocks.push_back(p);
		return p;
	}

	void deallocate(void* memory, std::size_t /*sizeInBytes*/ = 0, std::size_t /*alignment*/ = 0)
	{
		auto it = std::find(_blocks.begin(), _blocks.end(), memory);
		if (it != _blocks.end())
			_blocks.erase(it);
		::operator delete(memory);
	}

	void release()
	{
		for (void* p : _blocks)
			::operator delete(p);
		_blocks.clear();
	}
};

/**
*	@brief Simple allocator that uses a chunk-based pool to serve requests.
*/
class CMiniMem
{
private:
	static inline CMiniMem* _instance = nullptr;

	CMiniPool _pool;

	std::vector<CBaseParticle*> _particles;
	std::size_t _visibleParticles = 0;

protected:
	// private constructor and destructor.
	CMiniMem() = default;
	~CMiniMem() = default;

public:
	void* Allocate(std::size_t sizeInBytes, std::size_t alignment = alignof(std::max_align_t));

	void Deallocate(void* memory, std::size_t sizeInBytes, std::size_t alignment = alignof(std::max_align_t));

	void ProcessAll(); //Processes all

	void Reset(); //clears memory, setting all particles to not used.

	void Shutdown();

	int ApplyForce(Vector vOrigin, Vector vDirection, float flRadius, float flStrength);

	static CMiniMem* Instance();

	std::size_t GetTotalParticles() { return _particles.size(); }
	std::size_t GetDrawnParticles() { return _visibleParticles; }
};
