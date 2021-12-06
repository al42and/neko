/**
 * Device kernel for convective terms
 */

template< typename T, const int LX, const int CHUNKS >
__global__ void conv1_kernel(T * __restrict__ du,
			     const T * __restrict__ u,
			     const T * __restrict__ vx,
			     const T * __restrict__ vy,
			     const T * __restrict__ vz,
			     const T * __restrict__ dx,
			     const T * __restrict__ dy,
			     const T * __restrict__ dz,
			     const T * __restrict__ drdx,
			     const T * __restrict__ dsdx,
			     const T * __restrict__ dtdx,
			     const T * __restrict__ drdy,
			     const T * __restrict__ dsdy,
			     const T * __restrict__ dtdy,
			     const T * __restrict__ drdz,
			     const T * __restrict__ dsdz,
			     const T * __restrict__ dtdz,
			     const T * __restrict__ jacinv) { 

  __shared__ T shu[LX * LX * LX];

  __shared__ T shvx[LX * LX * LX];
  __shared__ T shvy[LX * LX * LX];
  __shared__ T shvz[LX * LX * LX];
  
  __shared__ T shdx[LX * LX];
  __shared__ T shdy[LX * LX];
  __shared__ T shdz[LX * LX];
  
  __shared__ T shjacinv[LX * LX * LX];

  
  int i,j,k;
  
  const int e = blockIdx.x;
  const int iii = threadIdx.x;
  const int nchunks = (LX * LX * LX - 1) / CHUNKS + 1;

  if (iii < (LX * LX)) {
    shdx[iii] = dx[iii];
    shdy[iii] = dy[iii];
    shdz[iii] = dz[iii];
  }

  j = iii;
  while(j < (LX * LX * LX)) {
    shu[j] = u[j + e * LX * LX * LX];

    shvx[j] = vx[j + e * LX * LX * LX];
    shvy[j] = vy[j + e * LX * LX * LX];
    shvz[j] = vz[j + e * LX * LX * LX];
    
    shjacinv[j] = jacinv[j + e * LX * LX * LX];

    j = j + CHUNKS;
  }
  
  __syncthreads();
  
  for (int n = 0; n < nchunks; n++) {
    const int ijk = iii + n * CHUNKS;
    const int jk = ijk / LX;
    i = ijk - jk * LX;
    k = jk / LX;
    j = jk - k * LX;
    if ( i < LX && j < LX && k < LX) {
      T rtmp = 0.0;
      T stmp = 0.0;
      T ttmp = 0.0;
      for (int l = 0; l < LX; l++) {		
	rtmp += shdx[i + l * LX] * shu[l + j * LX + k * LX * LX];	
	stmp += shdy[j + l * LX] * shu[i + l * LX + k * LX * LX];
	ttmp += shdz[k + l * LX] * shu[i + j * LX + l * LX * LX];
      }
      
      du[ijk + e * LX * LX * LX] = shjacinv[ijk] *
	(shvx[ijk] * (drdx[ijk + e * LX * LX * LX] * rtmp
		      + dsdx[ijk + e * LX * LX * LX] * stmp
		      + dtdx[ijk + e * LX * LX * LX] * ttmp)
	 + shvy[ijk] * (drdy[ijk + e * LX * LX * LX] * rtmp
			+ dsdy[ijk + e * LX * LX * LX] * stmp
			+ dtdy[ijk + e * LX * LX * LX] * ttmp)
	 + shvz[ijk] * (drdz[ijk + e * LX * LX * LX] * rtmp
			+ dsdz[ijk + e * LX * LX * LX] * stmp
			+ dtdz[ijk + e * LX * LX * LX] * ttmp));
    }
  }  
}

