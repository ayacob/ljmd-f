Subroutine force 

 USE kinds
  USE utils
  USE mdsys
  USE cell
  IMPLICIT NONE
integer x
print*, 'type 1 to choose LJ_pot 2 for Morse_pot'
  if (x .eq.1) then
     call force_Lj
  else
    call force_Morse
  end if
end subroutine

SUBROUTINE force_Lj
  USE kinds
  USE utils
  USE mdsys
  USE cell
  IMPLICIT NONE

  REAL(kind=dbl) :: rsq, rcutsq, rinv, pos1(3), delta(3)
  REAL(kind=dbl) :: boxby2, c12, c6, r6, ffac
  INTEGER :: i, j, k, n, m, ii, jj, kk, tid, fromidx, toidx
  INTEGER, EXTERNAL :: omp_get_thread_num
 
  epot=0.0_dbl

  !$OMP parallel default(SHARED) reduction(+:epot)              &
  !$OMP private(i,j,k,n,m,ii,jj,kk,tid,fromidx,toidx)           &
  !$OMP private(boxby2,c12,c6,r6,ffac,rsq,rcutsq,rinv,pos1,delta)
  tid = 0
  !$ tid = omp_get_thread_num() 
  tid = tid + 1
  frc(:,:,tid) = 0.0_dbl

  ! precompute some constants
  boxby2=0.5_dbl*box
  rcutsq=rcut*rcut
  c12 = 4.0_dbl*epsilon*sigma**12
  c6  = 4.0_dbl*epsilon*sigma**6

  ! first compute per cell self-interactions
  DO kk=0, ncell-1, nthreads
     i = kk + tid
     IF (i > ncell) EXIT

     DO j=1,npercell(i)-1
        ii = clist(i,j)
        pos1 = pos(ii,:)

        DO k=j+1,npercell(i)
           jj = clist(i,k)
           delta(1)=pbc(pos1(1)-pos(jj,1), boxby2, box)
           delta(2)=pbc(pos1(2)-pos(jj,2), boxby2, box)
           delta(3)=pbc(pos1(3)-pos(jj,3), boxby2, box)
           rsq = dot_product(delta,delta)
      
           ! compute force and energy if within cutoff */
           IF (rsq < rcutsq) THEN
              rinv = 1.0_dbl/rsq
              r6 = rinv*rinv*rinv
              ffac = (12.0_dbl*c12*r6 - 6.0_dbl*c6)*r6*rinv
              epot = epot + r6*(c12*r6 - c6)

              frc(ii,:,tid) = frc(ii,:,tid) + delta*ffac
              frc(jj,:,tid) = frc(jj,:,tid) - delta*ffac
           END IF
        END DO
     END DO
  END DO

  ! now compute per cell-cell interactions from pair list
  DO kk=0, npair-1, nthreads
     n = kk + tid
     IF (n > npair) EXIT
        
     i = plist(2*n-1)
     m = plist(2*n)
     DO j=1,npercell(i)
        ii = clist(i,j)
        pos1 = pos(ii,:)

        DO k=1,npercell(m)
           jj = clist(m,k)
           delta(1)=pbc(pos1(1)-pos(jj,1), boxby2, box)
           delta(2)=pbc(pos1(2)-pos(jj,2), boxby2, box)
           delta(3)=pbc(pos1(3)-pos(jj,3), boxby2, box)
           rsq = dot_product(delta,delta)
      
           ! compute force and energy if within cutoff */
           IF (rsq < rcutsq) THEN
              rinv = 1.0_dbl/rsq
              r6 = rinv*rinv*rinv
              ffac = (12.0_dbl*c12*r6 - 6.0_dbl*c6)*r6*rinv
              epot = epot + r6*(c12*r6 - c6)

              frc(ii,:,tid) = frc(ii,:,tid) + delta*ffac
              frc(jj,:,tid) = frc(jj,:,tid) - delta*ffac
           END IF
        END DO
     END DO
  END DO
  ! before reducing the forces, we have to make sure 
  ! that all threads are done adding to them.
  !$OMP barrier

  IF (nthreads > 1) THEN
     ! set equal chunks of index ranges
     i = 1 + (natoms/nthreads)
     fromidx = (tid-1)*i + 1
     toidx = fromidx + i - 1
     IF (toidx > natoms) toidx = natoms

     ! now reduce forces from threads with tid > 1 into
     ! the storage of the first thread. since we have
     ! threads already spawned, we do this in parallel.
     DO i=2,nthreads
        DO j=fromidx,toidx
           frc(j,:,1) = frc(j,:,1) + frc(j,:,i)
        END DO
     END DO
  END IF
  !$OMP END PARALLEL
END SUBROUTINE force_Lj





SUBROUTINE force_Morse
  USE kinds
  USE utils
  USE mdsys
  USE cell
  IMPLICIT NONE

  REAL(kind=dbl) :: rsq, rcutsq, rinv, pos1(3), delta(3),alpha,de,expcoff !re, alpha,& de const
  REAL(kind=dbl) :: boxby2 , de_alpha, rij, re,ffac!, c12, c6, r6
  INTEGER :: i, j, k, n, m, ii, jj, kk, tid, fromidx, toidx
  INTEGER, EXTERNAL :: omp_get_thread_num

epot=0.0_dbl

  !$OMP parallel default(SHARED) reduction(+:epot)              &
  !$OMP private(i,j,k,n,m,ii,jj,kk,tid,fromidx,toidx)           &
  !$OMP private(boxby2,c12,c6,r6,ffac,rsq,rcutsq,rinv,pos1,delta)
  tid = 0
  re=1.2
  de= 0.176
  alpha= 1.4
  !$ tid = omp_get_thread_num() 
  tid = tid + 1
  frc(:,:,tid) = 0.0_dbl
  de_alpha = de*(alpha**2)
  ! precompute some constants
  boxby2=0.5_dbl*box
  rcutsq=rcut*rcut

 ! c12 = 4.0_dbl*epsilon*sigma**12
!  c6  = 4.0_dbl*epsilon*sigma**6

  ! first compute per cell self-interactions
  DO kk=0, ncell-1, nthreads
     i = kk + tid
     IF (i > ncell) EXIT

     DO j=1,npercell(i)-1
        ii = clist(i,j)
        pos1 = pos(ii,:)

        DO k=j+1,npercell(i)
           jj = clist(i,k)
           delta(1)=pbc(pos1(1)-pos(jj,1), boxby2, box)
           delta(2)=pbc(pos1(2)-pos(jj,2), boxby2, box)
           delta(3)=pbc(pos1(3)-pos(jj,3), boxby2, box)
           rsq = dot_product(delta,delta)
           rij=sqrt(rsq)
           ! compute force and energy if within cutoff */
           IF (rsq < rcutsq) THEN
		 expcoff= -alpha*(rij-re)
              rinv = 2*de_alpha*(1.0_dbl/rij)
              !r6 = rinv*rinv*rinv
              ffac = (exp(expcoff)-exp(2*expcoff))
              epot = epot + de*(exp(2*expcoff)-2*exp(expcoff))

              frc(ii,:,tid) = frc(ii,:,tid) + delta*ffac*rinv
              frc(jj,:,tid) = frc(jj,:,tid) - delta*ffac*rinv
             END IF
        END DO
     END DO
  END DO

  ! now compute per cell-cell interactions from pair list
  DO kk=0, npair-1, nthreads
     n = kk + tid
     IF (n > npair) EXIT
        
     i = plist(2*n-1)
     m = plist(2*n)
     DO j=1,npercell(i)
        ii = clist(i,j)
        pos1 = pos(ii,:)

        DO k=1,npercell(m)
           jj = clist(m,k)
           delta(1)=pbc(pos1(1)-pos(jj,1), boxby2, box)
           delta(2)=pbc(pos1(2)-pos(jj,2), boxby2, box)
           delta(3)=pbc(pos1(3)-pos(jj,3), boxby2, box)
           rsq = dot_product(delta,delta)
      
           ! compute force and energy if within cutoff */
          IF (rsq < rcutsq) THEN
		 expcoff= -alpha*(rij-re)
              rinv = 2*de_alpha*(1.0_dbl/rij)
              !r6 = rinv*rinv*rinv
              ffac = (exp(expcoff)-exp(2*expcoff))
              epot = epot + de*(exp(2*expcoff)-2*exp(expcoff))

              frc(ii,:,tid) = frc(ii,:,tid) + delta*ffac*rinv
              frc(jj,:,tid) = frc(jj,:,tid) - delta*ffac*rinv
           END IF
        END DO
     END DO
  END DO
  ! before reducing the forces, we have to make sure 
  ! that all threads are done adding to them.
  !$OMP barrier

  IF (nthreads > 1) THEN
     ! set equal chunks of index ranges
     i = 1 + (natoms/nthreads)
     fromidx = (tid-1)*i + 1
     toidx = fromidx + i - 1
     IF (toidx > natoms) toidx = natoms

     ! now reduce forces from threads with tid > 1 into
     ! the storage of the first thread. since we have
     ! threads already spawned, we do this in parallel.
     DO i=2,nthreads
        DO j=fromidx,toidx
           frc(j,:,1) = frc(j,:,1) + frc(j,:,i)
        END DO
     END DO
  END IF
  !$OMP END PARALLEL
END SUBROUTINE force_Morse
