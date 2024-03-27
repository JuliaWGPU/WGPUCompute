using Revise
using WGPUCompute
using Test
using StaticArrays

const Vec2{T} = SVector{2, T}
const Vec3{T} = SVector{3, T}
const Vec4{T} = SVector{4, T}
const Mat2{T} = SMatrix{2, 2, T, 4}
const Mat3{T} = SMatrix{3, 3, T, 9}
const Mat4{T} = SMatrix{4, 4, T, 16}
const Vec{N, T} = SVector{N, T}

x = WgpuArray{Float32, 2}(rand(16, 16));
y = WgpuArray{Float32, 2}(rand(16, 16));

function tiled_matmul_kernel(x::WgpuArray{T, N}, y::WgpuArray{T, N}, out::WgpuArray{T, N}) where {T, N}
	lIdx = localId.x
	lIdy = localId.y
	gIdx = globalId.x
	gIdy = globalId.y
	
	#set out matrix to zero
	gId = xDims.x*gIdy + gIdx
	out[gId] = 0.0
	
	# set local variable = 0.0
	sum = 0.0
	
	for tileId in 0:numWorkgroups.y
		# copy block from x to shared memory
		xId = workgroupId.x*workgroupDims.x + localId.x
		yId = tileId*workgroupDims.y + localId.y
		sId = localId.y*workgroupDims.x + localId.x
		shmem1[sId] = x[yId*xDims.x + xId]
		
		# copy block from y to shared memory
		xId = tileId*workgroupDims.x + localId.x
		yId = workgroupId.y*workgroupDims.y + localId.y
		shmem2[sId] = y[yId*yDims.x + xId]
		synchronize()
		
		# block sums for each tid
		for i in 0:workgroupDims.y
			sum = sum + shmem1[i*workgroupDims.x + localId.x]*shmem2[localId.y*workgroupDims.x + i]
		end
		synchronize()
	end
	
	out[gId] = sum
end

function tiled_matmul(x::WgpuArray{T, N}, y::WgpuArray{T, N}) where {T, N}
	aSize = size(x)
	bSize = size(y)
	@assert last(aSize) == first(bSize)
	outSize = (first(aSize), last(bSize))
	@assert eltype(x) == eltype(y)
	out = WgpuArray{eltype(x), ndims(x)}(undef, outSize)
	wgSize = (16, 16)
	@wgpukernel(
		launch=true,
		workgroupSizes=(4, 4),
		workgroupCount=(4, 4),
		shmem=(:shmem1=>(Float32, (4, 4)), :shmem2=>(Float32, (4, 4))),
		tiled_matmul_kernel(x, y, out)
	)
	return out
end

Base.:*(x::WgpuArray{T, N}, y::WgpuArray{T, N})  where {T, N} = tiled_matmul(x, y)

z = x*y

z_cpu = (x |> collect)*(y |> collect)

@test z_cpu ≈ (z |> collect)
