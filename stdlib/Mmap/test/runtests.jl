# This file is a part of Julia. License is MIT: https://julialang.org/license

using Test, Mmap, Random

file = tempname()
write(file, "Hello World\n")
t = b"Hello World"
@test mmap(file, Array{UInt8,3}, (11,1,1)) == reshape(t,(11,1,1))
GC.gc(); GC.gc()
@test mmap(file, Array{UInt8,3}, (1,11,1)) == reshape(t,(1,11,1))
GC.gc(); GC.gc()
@test mmap(file, Array{UInt8,3}, (1,1,11)) == reshape(t,(1,1,11))
GC.gc(); GC.gc()
@test mmap(file, Array{UInt8,3}, (11,0,1)) == Array{UInt8}(undef, (0,0,0))
@test mmap(file, Vector{UInt8}, (11,)) == t
GC.gc(); GC.gc()
@test mmap(file, Array{UInt8,2}, (1,11)) == t'
GC.gc(); GC.gc()
@test mmap(file, Array{UInt8,2}, (0,12)) == Array{UInt8}(undef, (0,0))
m = mmap(file, Array{UInt8,3}, (1,2,1))
@test m == reshape(b"He",(1,2,1))
finalize(m); m=nothing; GC.gc()

# constructors
@test length(@inferred mmap(file)) == 12
@test length(@inferred mmap(file, Vector{Int8})) == 12
@test length(@inferred mmap(file, Matrix{Int8}, (12,1))) == 12
@test length(@inferred mmap(file, Matrix{Int8}, (12,1), 0)) == 12
@test length(@inferred mmap(file, Matrix{Int8}, (12,1), 0; grow=false)) == 12
@test length(@inferred mmap(file, Matrix{Int8}, (12,1), 0; shared=false)) == 12
@test length(@inferred mmap(file, Vector{Int8}, 12)) == 12
@test length(@inferred mmap(file, Vector{Int8}, 12, 0)) == 12
@test length(@inferred mmap(file, Vector{Int8}, 12, 0; grow=false)) == 12
@test length(@inferred mmap(file, Vector{Int8}, 12, 0; shared=false)) == 12
s = open(file)
@test length(@inferred mmap(s)) == 12
@test length(@inferred mmap(s, Vector{Int8})) == 12
@test length(@inferred mmap(s, Matrix{Int8}, (12,1))) == 12
@test length(@inferred mmap(s, Matrix{Int8}, (12,1), 0)) == 12
@test length(@inferred mmap(s, Matrix{Int8}, (12,1), 0; grow=false)) == 12
@test length(@inferred mmap(s, Matrix{Int8}, (12,1), 0; shared=false)) == 12
@test length(@inferred mmap(s, Vector{Int8}, 12)) == 12
@test length(@inferred mmap(s, Vector{Int8}, 12, 0)) == 12
@test length(@inferred mmap(s, Vector{Int8}, 12, 0; grow=false)) == 12
@test length(@inferred mmap(s, Vector{Int8}, 12, 0; shared=false)) == 12
close(s)
@test_throws ArgumentError mmap(file, Vector{Ref}) # must be bit-type
GC.gc(); GC.gc()

file = tempname() # new name to reduce chance of issues due slow windows fs
s = open(f->f,file,"w")
@test mmap(file) == Vector{UInt8}() # requested len=0 on empty file
@test mmap(file,Vector{UInt8},0) == Vector{UInt8}()
s = open(file, "r+")
m = mmap(s,Vector{UInt8},12)
m[:] = b"Hello World\n"
Mmap.sync!(m)
close(s); finalize(m); m=nothing; GC.gc()
@test open(x->read(x, String),file) == "Hello World\n"

s = open(file, "r")
close(s)
@test_throws Base.IOError mmap(s) # closed IOStream
@test_throws ArgumentError mmap(s,Vector{UInt8},12,0) # closed IOStream
@test_throws SystemError mmap("")

# negative length
@test_throws ArgumentError mmap(file, Vector{UInt8}, -1)
# negative offset
@test_throws ArgumentError mmap(file, Vector{UInt8}, 1, -1)

for i = 0x01:0x0c
    @test length(mmap(file, Vector{UInt8}, i)) == Int(i)
end
GC.gc(); GC.gc()

sz = filesize(file)
s = open(file, "r+")
m = mmap(s, Vector{UInt8}, sz+1)
@test length(m) == sz+1 # test growing
@test m[end] == 0x00
close(s); finalize(m); m=nothing; GC.gc()
sz = filesize(file)
s = open(file, "r+")
m = mmap(s, Vector{UInt8}, 1, sz)
@test length(m) == 1
@test m[1] == 0x00
close(s); finalize(m); m=nothing; GC.gc()
sz = filesize(file)
# test where offset is actually > than size of file; file is grown with zeroed bytes
s = open(file, "r+")
m = mmap(s, Vector{UInt8}, 1, sz+1)
@test length(m) == 1
@test m[1] == 0x00
close(s); finalize(m); m=nothing; GC.gc()

# See https://github.com/JuliaLang/julia/issues/32155
# On PPC we receive `SEGV_MAPERR` instead of `SEGV_ACCERR` and
# can thus not turn the segmentation fault into an exception.
if !(Sys.ARCH === :powerpc64le || Sys.ARCH === :ppc64le)
    s = open(file, "r")
    m = mmap(s)
    @test_throws ReadOnlyMemoryError m[5] = UInt8('x') # tries to setindex! on read-only array
    finalize(m); m=nothing;
end
GC.gc()
write(file, "Hello World\n")

s = open(file, "r")
m = mmap(s)
close(s)
finalize(m); m=nothing; GC.gc()
m = mmap(file)
s = open(file, "r+")
c = mmap(s)
d = mmap(s)
c[1] = UInt8('J')
Mmap.sync!(c)
close(s)
@test m[1] == UInt8('J')
@test d[1] == UInt8('J')
finalize(m); finalize(c); finalize(d)
m=nothing; c=nothing; d=nothing; GC.gc()

write(file, "Hello World\n")

s = open(file, "r")
@test isreadonly(s) == true
c = mmap(s, Vector{UInt8}, (11,))
@test c == b"Hello World"
finalize(c); c=nothing; GC.gc()
c = mmap(s, Vector{UInt8}, (UInt16(11),))
@test c == b"Hello World"
finalize(c); c=nothing; GC.gc()
@test_throws ArgumentError mmap(s, Vector{UInt8}, (Int16(-11),))
@test_throws ArgumentError mmap(s, Vector{UInt8}, (typemax(UInt),))
@test_throws ArgumentError mmap(s, Matrix{UInt8}, (typemax(Int) - Mmap.PAGESIZE - 1, 2)) # overflow
close(s)
s = open(file, "r+")
@test isreadonly(s) == false
c = mmap(s, Vector{UInt8}, (11,))
c[5] = UInt8('x')
Mmap.sync!(c)
close(s)
s = open(file, "r")
str = readline(s)
close(s)
@test startswith(str, "Hellx World")
finalize(c); c=nothing; GC.gc()

c = mmap(file)
@test c == b"Hellx World\n"
finalize(c); c=nothing; GC.gc()
c = mmap(file, Vector{UInt8}, 3)
@test c == b"Hel"
finalize(c); c=nothing; GC.gc()
s = open(file, "r")
c = mmap(s, Vector{UInt8}, 6)
@test c == b"Hellx "
close(s)
finalize(c); c=nothing; GC.gc()
c = mmap(file, Vector{UInt8}, 5, 6)
@test c == b"World"
finalize(c); c=nothing; GC.gc()

s = open(file, "w")
write(s, "Hello World\n")
close(s)

# test mmap
m = mmap(file)
tdata = b"Hello World\n"
for i = 1:12
    @test m[i] == tdata[i]
end
@test_throws BoundsError m[13]
finalize(m); m=nothing; GC.gc()

m = mmap(file,Vector{UInt8},6)
@test m[1] == b"H"[1]
@test m[2] == b"e"[1]
@test m[3] == b"l"[1]
@test m[4] == b"l"[1]
@test m[5] == b"o"[1]
@test m[6] == b" "[1]
@test_throws BoundsError m[7]
finalize(m); m=nothing; GC.gc()

m = mmap(file,Vector{UInt8},2,6)
@test m[1] == b"W"[1]
@test m[2] == b"o"[1]
@test_throws BoundsError m[3]
finalize(m); m = nothing; GC.gc()

file = tempname() # new name to reduce chance of issues due slow windows fs
s = open(file, "w")
write(s, [0xffffffffffffffff,
          0xffffffffffffffff,
          0xffffffffffffffff,
          0x000000001fffffff])
close(s)
s = open(file, "r")
@test isreadonly(s)
b = @inferred mmap(s, BitArray, (17,13))
@test Test._check_bitarray_consistency(b)
@test b == trues(17,13)
@test_throws ArgumentError mmap(s, BitArray, (7,3))
close(s)
s = open(file, "r+")
b = mmap(s, BitArray, (17,19))
@test Test._check_bitarray_consistency(b)
rand!(b)
Mmap.sync!(b)
b0 = copy(b)
@test Test._check_bitarray_consistency(b0)
close(s)
s = open(file, "r")
@test isreadonly(s)
b = mmap(s, BitArray, (17,19))
@test Test._check_bitarray_consistency(b)
@test b == b0
close(s)
finalize(b); finalize(b0)
b = nothing; b0 = nothing
GC.gc()

open(file,"w") do f
    write(f,UInt64(1))
    write(f,UInt8(1))
end
@test filesize(file) == 9
s = open(file, "r+")
m = mmap(s, BitArray, (72,))
@test Test._check_bitarray_consistency(m)
@test length(m) == 72
close(s); finalize(m); m = nothing; GC.gc()

m = mmap(file, BitArray, (72,))
@test Test._check_bitarray_consistency(m)
@test length(m) == 72
finalize(m); m = nothing; GC.gc()

s = open(file, "r+")
m = mmap(s, BitArray, 72) # len integer instead of dims
@test Test._check_bitarray_consistency(m)
@test length(m) == 72
close(s); finalize(m); m = nothing; GC.gc()

m = mmap(file, BitArray, 72) # len integer instead of dims
@test Test._check_bitarray_consistency(m)
@test length(m) == 72
finalize(m); m = nothing; GC.gc()
rm(file)

# mmap with an offset
A = rand(1:20, 500, 300)
fname = tempname()
s = open(fname, "w+")
write(s, size(A,1))
write(s, size(A,2))
write(s, A)
close(s)
s = open(fname)
m = read(s, Int)
n = read(s, Int)
A2 = mmap(s, Matrix{Int}, (m,n))
@test A == A2
seek(s, 0)
A3 = mmap(s, Matrix{Int}, (m,n), convert(Int64, 2*sizeof(Int)))
@test A == A3
A4 = mmap(s, Matrix{Int}, (m,150), convert(Int64, (2+150*m)*sizeof(Int)))
@test A[:, 151:end] == A4
close(s)
finalize(A2); finalize(A3); finalize(A4)
A2 = A3 = A4 = nothing
GC.gc()
rm(fname)

# Mmap.Anonymous
m = Mmap.Anonymous()
@test m.name == ""
@test !m.readonly
@test m.create
@test isopen(m)
@test isreadable(m)
@test iswritable(m)

m = mmap(Vector{UInt8}, 12)
@test length(m) == 12
@test all(m .== 0x00)
@test m[1] === 0x00
@test m[end] === 0x00
m[1] = 0x0a
Mmap.sync!(m)
@test m[1] === 0x0a
m = mmap(Vector{UInt8}, 12; shared=false)
m = mmap(Vector{Int}, 12)
@test length(m) == 12
@test all(m .== 0)
@test m[1] === 0
@test m[end] === 0
m = mmap(Vector{Float64}, 12)
@test length(m) == 12
@test all(m .== 0.0)
m = mmap(Matrix{Int8}, (12,12))
@test size(m) == (12,12)
@test all(m == zeros(Int8, (12,12)))
@test sizeof(m) == prod((12,12))
n = similar(m)
@test size(n) == (12,12)
n = similar(m, (2,2))
@test size(n) == (2,2)
n = similar(m, 12)
@test length(n) == 12
@test size(n) == (12,)
finalize(m); m = nothing; GC.gc()

if Sys.isunix()
    file = tempname()
    write(file, rand(Float64, 20))
    A = mmap(file, Vector{Float64}, 20)
    @test Mmap.madvise!(A, Mmap.MADV_WILLNEED) === nothing # checking for no error
    finalize(A); A = nothing; GC.gc()

    write(file, BitArray(rand(Bool, 20)))
    b = mmap(file, BitArray, 20)
    @test Mmap.madvise!(b, Mmap.MADV_WILLNEED) === nothing
    finalize(b); b = nothing; GC.gc()
    rm(file)
end

# test #14885
file = tempname()
touch(file)
open(file, "r+") do s
    A = mmap(s, Vector{UInt8}, (10,), 0)
    Mmap.sync!(A)
    finalize(A); A = nothing; GC.gc()
    A = mmap(s, Vector{UInt8}, (10,), 1)
    Mmap.sync!(A)
    finalize(A); A = nothing;
end
GC.gc()
rm(file)

# test for #58982 - mmap with primitive types
file = tempname()
primitive type PrimType9Bytes 9*8 end
arr = Vector{PrimType9Bytes}(undef, 2)
write(file, arr)
m = mmap(file, Vector{PrimType9Bytes})
@test length(m) == 2
@test m[1] == arr[1]
@test m[2] == arr[2]
finalize(m); m = nothing; GC.gc()
rm(file)


@testset "Docstrings" begin
    @test isempty(Docs.undocumented_names(Mmap))
end
