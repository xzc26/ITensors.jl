
mutable struct ProjMPO
  lpos::Int
  rpos::Int
  nsite::Int
  H::MPO
  LR::Vector{ITensor}
  ProjMPO(H::MPO) = new(0,
                        length(H) + 1,
                        2,
                        H,
                        Vector{ITensor}(undef, length(H)))
end

nsite(pm::ProjMPO) = pm.nsite

Base.length(pm::ProjMPO) = length(pm.H)

function lproj(pm::ProjMPO)
  (pm.lpos <= 0) && return nothing
  return pm.LR[pm.lpos]
end

function rproj(pm::ProjMPO)
  (pm.rpos >= length(pm)+1) && return nothing
  return pm.LR[pm.rpos]
end

function product(pm::ProjMPO,
                 v::ITensor)::ITensor
  Hv = v
  if isnothing(lproj(pm))
    if !isnothing(rproj(pm))
      Hv *= rproj(pm)
    end
    for j in pm.rpos-1:-1:pm.lpos+1
      Hv *= pm.H[j]
    end
  else #if lproj exists
    Hv *= lproj(pm)
    for j in pm.lpos+1:pm.rpos-1
      Hv *= pm.H[j]
    end
    if !isnothing(rproj(pm))
      Hv *= rproj(pm)
    end
  end
  return noprime(Hv)
end

function Base.eltype(pm::ProjMPO)
  elT = eltype(pm.H[pm.lpos+1])
  for j in pm.lpos+2:pm.rpos-1
    elT = promote_type(elT, eltype(pm.H[j]))
  end
  if !isnothing(lproj(pm))
    elT = promote_type(elT, eltype(lproj(pm)))
  end
  if !isnothing(rproj(pm))
    elT = promote_type(elT, eltype(rproj(pm)))
  end
  return elT
end

(pm::ProjMPO)(v::ITensor) = product(pm,v)

function Base.size(pm::ProjMPO)::Tuple{Int,Int}
  d = 1
  if !isnothing(lproj(pm))
    for i in inds(lproj(pm))
      plev(i) > 0 && (d *= dim(i))
    end
  end
  for j in pm.lpos+1:pm.rpos-1
    for i in inds(pm.H[j])
      plev(i) > 0 && (d *= dim(i))
    end
  end
  if !isnothing(rproj(pm))
    for i in inds(rproj(pm))
      plev(i) > 0 && (d *= dim(i))
    end
  end
  return (d,d)
end

function makeL!(pm::ProjMPO,
                psi::MPS,
                k::Int)
  while pm.lpos < k
    ll = pm.lpos
    if ll <= 0
      pm.LR[1] = psi[1]*pm.H[1]*dag(prime(psi[1]))
      pm.lpos = 1
    else
      pm.LR[ll+1] = pm.LR[ll]*psi[ll+1]*pm.H[ll+1]*dag(prime(psi[ll+1]))
      pm.lpos += 1
    end
  end
end

function makeR!(pm::ProjMPO,
                psi::MPS,
                k::Int)
  N = length(pm.H)
  while pm.rpos > k
    rl = pm.rpos
    if rl >= N+1
      pm.LR[N] = psi[N]*pm.H[N]*dag(prime(psi[N]))
      pm.rpos = N
    else
      pm.LR[rl-1] = pm.LR[rl]*psi[rl-1]*pm.H[rl-1]*dag(prime(psi[rl-1]))
      pm.rpos -= 1
    end
  end
end

function position!(pm::ProjMPO,
                   psi::MPS, 
                   pos::Int)
  makeL!(pm,psi,pos-1)
  makeR!(pm,psi,pos+nsite(pm))

  #These next two lines are needed 
  #when moving lproj and rproj backward
  pm.lpos = pos-1
  pm.rpos = pos+nsite(pm)
end

# Return a "noise term" as in Phys. Rev. B 72, 180403
function noiseterm(pm::ProjMPO,
                   phi::ITensor,
                   b::Int,
                   ortho::String)
  if ortho == "left"
    nt = pm.H[b]*phi
    if !isnothing(lproj(pm))
      nt *= lproj(pm)
    end
  elseif ortho == "right"
    nt = phi*pm.H[b+1]
    if !isnothing(rproj(pm))
      nt *= rproj(pm)
    end
  else
    error("In noiseterm, got ortho = $ortho, only supports `left` and `right`")
  end
  nt = nt*dag(noprime(nt))
  return nt
end

