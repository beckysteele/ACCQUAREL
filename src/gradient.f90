MODULE gradient_mod
CONTAINS
! performs a linesearch about PDM
FUNCTION LINESEARCH(CMT,PDM,NBAST,POEFM,PHI) RESULT(PDMNEW)
  USE case_parameters ; USE data_parameters ; USE basis_parameters ; USE common_functions
  USE matrices ; USE matrix_tools ; USE metric_relativistic ; USE scf_tools ; USE output
  USE esa_mod
  IMPLICIT NONE
  INTEGER,INTENT(IN) :: NBAST
  DOUBLE COMPLEX,DIMENSION(NBAST*(NBAST+1)/2),INTENT(IN) :: POEFM
  DOUBLE COMPLEX,DIMENSION(NBAST,NBAST) :: CMT
  TYPE(twospinor),DIMENSION(NBAST),INTENT(IN) :: PHI
  INTEGER :: I
  DOUBLE PRECISION :: ETOT,EPS
  DOUBLE COMPLEX,DIMENSION(NBAST*(NBAST+1)/2) :: PTEFM,PFM,PDM,PDMNEW

  DOUBLE PRECISION,PARAMETER :: EPS_FINDIFF = 0.001
  CHARACTER(1),PARAMETER :: ALGORITHM = 'F'

  ! compute EPS
  IF(ALGORITHM == 'F') THEN
     ! fixed 
     EPS = 0.1
  ELSEIF(ALGORITHM == 'Q') THEN
     ! quadratic model
  END IF
  
  PDMNEW=PACK(MATMUL(MATMUL(MATMUL(MATMUL(EXPONENTIAL(EPS,CMT,NBAST),UNPACK(PDM,NBAST)),&
       &UNPACK(PS,NBAST)),EXPONENTIAL(-EPS,CMT,NBAST)),UNPACK(PIS,NBAST)),NBAST)

  PDMNEW = THETA(PDMNEW,POEFM,NBAST,PHI,'D')
END FUNCTION LINESEARCH
END MODULE gradient_mod

SUBROUTINE GRADIENT_relativistic(EIG,EIGVEC,NBAST,POEFM,PHI,TRSHLD,MAXITR,RESUME)
! Roothaan's algorithm (closed-shell Dirac-Hartree-Fock formalism).
! Reference: C. C. J. Roothaan, New developments in molecular orbital theory, Rev. Modern Phys., 23(2), 69-89, 1951.
  USE case_parameters ; USE data_parameters ; USE basis_parameters ; USE common_functions
  USE matrices ; USE matrix_tools ; USE metric_relativistic ; USE scf_tools ; USE output
  USE esa_mod ; USE gradient_mod
  IMPLICIT NONE
  INTEGER,INTENT(IN) :: NBAST
  DOUBLE PRECISION,DIMENSION(NBAST),INTENT(OUT) :: EIG
  DOUBLE COMPLEX,DIMENSION(NBAST,NBAST),INTENT(OUT) :: EIGVEC
  DOUBLE COMPLEX,DIMENSION(NBAST*(NBAST+1)/2),INTENT(IN) :: POEFM
  DOUBLE COMPLEX,DIMENSION(NBAST,NBAST) :: CMT,ISRS
  TYPE(twospinor),DIMENSION(NBAST),INTENT(IN) :: PHI
  DOUBLE PRECISION,INTENT(IN) :: TRSHLD
  INTEGER,INTENT(IN) :: MAXITR
  LOGICAL,INTENT(IN) :: RESUME

  INTEGER :: ITER,LOON,INFO,I
  DOUBLE PRECISION :: ETOT,ETOT1
  DOUBLE COMPLEX,DIMENSION(:),ALLOCATABLE :: PTEFM,PFM,PDM,PDM1,PPM
  LOGICAL :: NUMCONV

! INITIALIZATION AND PRELIMINARIES
  ALLOCATE(PDM(1:NBAST*(NBAST+1)/2),PDM1(1:NBAST*(NBAST+1)/2))
  ALLOCATE(PTEFM(1:NBAST*(NBAST+1)/2),PFM(1:NBAST*(NBAST+1)/2))
  ALLOCATE(PPM(1:NBAST*(NBAST+1)/2))

  ITER=0
  PDM=(0.D0,0.D0)
  PTEFM=(0.D0,0.D0)
  ETOT1=0.D0
  OPEN(16,FILE='plots/rootenrgy.txt',STATUS='unknown',ACTION='write')
  OPEN(17,FILE='plots/rootcrit1.txt',STATUS='unknown',ACTION='write')
  OPEN(18,FILE='plots/rootcrit2.txt',STATUS='unknown',ACTION='write')

! LOOP
1 CONTINUE
  ITER=ITER+1
  WRITE(*,'(a)')' '
  WRITE(*,'(a,i3)')'# ITER = ',ITER

! Assembly and diagonalization of the Fock matrix
  PFM=POEFM+PTEFM
  CALL EIGENSOLVER(PFM,PCFS,NBAST,EIG,EIGVEC,INFO)
  IF (INFO/=0) GO TO 4
! Assembly of the density matrix according to the aufbau principle
  CALL CHECKORB(EIG,NBAST,LOON)
  PDM1=PDM
  CALL FORMDM(PDM,EIGVEC,NBAST,LOON,LOON+NBE-1)
! Computation of the energy associated to the density matrix
  CALL BUILDTEFM(PTEFM,NBAST,PHI,PDM)
  ETOT=ENERGY(POEFM,PTEFM,PDM,NBAST)
  WRITE(*,*)'E(D_n)=',ETOT
! Numerical convergence check
  CALL CHECKNUMCONV(PDM,PDM1,POEFM+PTEFM,NBAST,ETOT,ETOT1,TRSHLD,NUMCONV)
  IF (NUMCONV) THEN
! Convergence reached
     GO TO 2
  ELSE IF (ITER==MAXITR) THEN
! Maximum number of iterations reached without convergence
     GO TO 3
  ELSE
! Convergence not reached, increment
     ETOT1=ETOT
     GO TO 1
  END IF
! MESSAGES
2 WRITE(*,*)' ' ; WRITE(*,*)'Subroutine ROOTHAAN: convergence after',ITER,'iteration(s).'
  OPEN(9,FILE='eigenvalues.txt',STATUS='UNKNOWN',ACTION='WRITE')
  DO I=1,NBAST
     WRITE(9,'(i4,e22.14)')I,EIG(I)
  END DO
  CLOSE(9)
  GO TO 5
3 WRITE(*,*)' ' ; WRITE(*,*)'Subroutine ROOTHAAN: no convergence after',ITER,'iteration(s).'
  OPEN(9,FILE='eigenvalues.txt',STATUS='UNKNOWN',ACTION='WRITE')
  DO I=1,NBAST
     WRITE(9,'(i4,e22.14)')I,EIG(I)
  END DO
  CLOSE(9)
  GO TO 6
4 WRITE(*,*)'(called from subroutine ROOTHAAN)'
5 DEALLOCATE(PDM,PDM1,PTEFM,PFM)
  CLOSE(16) ; CLOSE(17) ; CLOSE(18)
  STOP

  ! Gradient algorithm
6 WRITE(*,*) ' '
  WRITE(*,*) 'Switching to gradient algorithm'
  WRITE(*,*) ' '
  ITER = 0
7 ITER=ITER+1
  WRITE(*,'(a)')' '
  WRITE(*,'(a,i3)')'# ITER = ',ITER

! Assembly and diagonalization of the Fock matrix
  PFM=POEFM+PTEFM
  CALL EIGENSOLVER(PFM,PCFS,NBAST,EIG,EIGVEC,INFO)
  IF (INFO/=0) GO TO 4

  ! computation of the commutator
  ! CMT in ON basis = DF - Sm1 F D S
  CMT = MATMUL(UNPACK(PDM,NBAST),UNPACK(PFM,NBAST)) - &
       MATMUL(MATMUL(MATMUL(UNPACK(PIS,NBAST),UNPACK(PFM,NBAST)),UNPACK(PDM,NBAST)),UNPACK(PS,NBAST))
  PDM1 = PDM
  ! PDM by line search
  PDM = LINESEARCH(CMT,PDM,NBAST,POEFM,PHI)
    
! Computation of the energy associated to the density matrix
  CALL BUILDTEFM(PTEFM,NBAST,PHI,PDM)
  ETOT=ENERGY(POEFM,PTEFM,PDM,NBAST)
  WRITE(*,*)'E(D_n)=',ETOT
  ! CALL OUTPUT_ITER(ITER,PDM,PHI,NBAST,EIG,EIGVEC,ETOT)
! Numerical convergence check
  CALL CHECKNUMCONV(PDM,PDM1,POEFM+PTEFM,NBAST,ETOT,ETOT1,TRSHLD,NUMCONV)
  IF (NUMCONV) THEN
! Convergence reached
     ! CALL OUTPUT_FINALIZE(ITER,PDM,PHI,NBAST,EIG,EIGVEC,ETOT)
     GO TO 2
  ELSE IF (ITER==200*MAXITR) THEN
! Maximum number of iterations reached without convergence
     GO TO 5
  ELSE
! Convergence not reached, increment
     ETOT1=ETOT
     GO TO 7
  END IF
END SUBROUTINE GRADIENT_relativistic

SUBROUTINE GRADIENT_RHF(EIG,EIGVEC,NBAST,POEFM,PHI,TRSHLD,MAXITR,RESUME)
! Roothaan's algorithm (closed-shell Dirac-Hartree-Fock formalism).
! Reference: C. C. J. Roothaan, New developments in molecular orbital theory, Rev. Modern Phys., 23(2), 69-89, 1951.
  USE case_parameters ; USE data_parameters ; USE basis_parameters ; USE common_functions
  USE matrices ; USE matrix_tools ; USE metric_nonrelativistic ; USE scf_tools ; USE output
  IMPLICIT NONE
  INTEGER,INTENT(IN) :: NBAST
  DOUBLE PRECISION,DIMENSION(NBAST),INTENT(OUT) :: EIG
  DOUBLE PRECISION,DIMENSION(NBAST,NBAST),INTENT(OUT) :: EIGVEC
  DOUBLE PRECISION,DIMENSION(NBAST*(NBAST+1)/2),INTENT(IN) :: POEFM
  DOUBLE PRECISION,DIMENSION(NBAST,NBAST) :: CMT,ISRS
  TYPE(gaussianbasisfunction),DIMENSION(NBAST),INTENT(IN) :: PHI
  DOUBLE PRECISION,INTENT(IN) :: TRSHLD
  INTEGER,INTENT(IN) :: MAXITR
  LOGICAL,INTENT(IN) :: RESUME

  INTEGER :: ITER,INFO,I
  DOUBLE PRECISION :: ETOT,ETOT1,EPS
  DOUBLE PRECISION,DIMENSION(:),ALLOCATABLE :: PTEFM,PFM,PDM,PDM1
  LOGICAL :: NUMCONV


! INITIALIZATION AND PRELIMINARIES
  ALLOCATE(PDM(1:NBAST*(NBAST+1)/2),PDM1(1:NBAST*(NBAST+1)/2))
  ALLOCATE(PTEFM(1:NBAST*(NBAST+1)/2),PFM(1:NBAST*(NBAST+1)/2))

  ITER=0
  PDM=(0.D0,0.D0)
  PTEFM=(0.D0,0.D0)
  ETOT1=0.D0
  OPEN(16,FILE='plots/rootenrgy.txt',STATUS='unknown',ACTION='write')
  OPEN(17,FILE='plots/rootcrit1.txt',STATUS='unknown',ACTION='write')
  OPEN(18,FILE='plots/rootcrit2.txt',STATUS='unknown',ACTION='write')

! LOOP
1 CONTINUE
  ITER=ITER+1
  WRITE(*,'(a)')' '
  WRITE(*,'(a,i3)')'# ITER = ',ITER

! Assembly and diagonalization of the Fock matrix
  PFM=POEFM+PTEFM
  CALL EIGENSOLVER(PFM,PCFS,NBAST,EIG,EIGVEC,INFO)
  IF (INFO/=0) GO TO 4
! Assembly of the density matrix according to the aufbau principle
  PDM1 = PDM
  CALL FORMDM(PDM,EIGVEC,NBAST,1,NBE/2)
! Computation of the energy associated to the density matrix
  CALL BUILDTEFM(PTEFM,NBAST,PHI,PDM)
  ETOT=ENERGY(POEFM,PTEFM,PDM,NBAST)
  WRITE(*,*)'E(D_n)=',ETOT
! Numerical convergence check
  CALL CHECKNUMCONV(PDM,PDM1,POEFM+PTEFM,NBAST,ETOT,ETOT1,TRSHLD,NUMCONV)
  IF (NUMCONV) THEN
! Convergence reached
     GO TO 2
  ELSE IF (ITER==MAXITR) THEN
! Maximum number of iterations reached without convergence
     GO TO 3
  ELSE
! Convergence not reached, increment
     ETOT1=ETOT
     GO TO 1
  END IF
! MESSAGES
2 WRITE(*,*)' ' ; WRITE(*,*)'Subroutine ROOTHAAN: convergence after',ITER,'iteration(s).'
  OPEN(9,FILE='eigenvalues.txt',STATUS='UNKNOWN',ACTION='WRITE')
  DO I=1,NBAST
     WRITE(9,'(i4,e22.14)')I,EIG(I)
  END DO
  CLOSE(9)
  GO TO 5
3 WRITE(*,*)' ' ; WRITE(*,*)'Subroutine ROOTHAAN: no convergence after',ITER,'iteration(s).'
  OPEN(9,FILE='eigenvalues.txt',STATUS='UNKNOWN',ACTION='WRITE')
  DO I=1,NBAST
     WRITE(9,'(i4,e22.14)')I,EIG(I)
  END DO
  CLOSE(9)
  GO TO 6
4 WRITE(*,*)'(called from subroutine ROOTHAAN)'
5 DEALLOCATE(PDM,PDM1,PTEFM,PFM)
  CLOSE(16) ; CLOSE(17) ; CLOSE(18)
  STOP

  ! Gradient algorithm
6 WRITE(*,*) ' '
  WRITE(*,*) 'Switching to gradient algorithm'
  WRITE(*,*) ' '
  ITER = 0
7 ITER=ITER+1
  WRITE(*,'(a)')' '
  WRITE(*,'(a,i3)')'# ITER = ',ITER

! Assembly and diagonalization of the Fock matrix
  PFM=POEFM+PTEFM
  CALL EIGENSOLVER(PFM,PCFS,NBAST,EIG,EIGVEC,INFO)
  IF (INFO/=0) GO TO 4

  ! computation of the commutator
  EPS = .05
  PDM1 = PDM
  ! CMT in ON basis = DF - Sm1 F D S
  CMT = MATMUL(UNPACK(PDM,NBAST),UNPACK(PFM,NBAST)) - &
       MATMUL(MATMUL(MATMUL(UNPACK(PIS,NBAST),UNPACK(PFM,NBAST)),UNPACK(PDM,NBAST)),UNPACK(PS,NBAST))
  PDM = PACK(MATMUL(MATMUL(MATMUL(MATMUL(EXPONENTIAL(EPS,CMT,NBAST),UNPACK(PDM,NBAST)),&
       UNPACK(PS,NBAST)),EXPONENTIAL(-EPS,CMT,NBAST)),UNPACK(PIS,NBAST)),NBAST)
  
! Computation of the energy associated to the density matrix
  CALL BUILDTEFM(PTEFM,NBAST,PHI,PDM)
  ETOT=ENERGY(POEFM,PTEFM,PDM,NBAST)
  WRITE(*,*)'E(D_n)=',ETOT
  ! CALL OUTPUT_ITER(ITER,PDM,PHI,NBAST,EIG,EIGVEC,ETOT)
! Numerical convergence check
  CALL CHECKNUMCONV(PDM,PDM1,POEFM+PTEFM,NBAST,ETOT,ETOT1,TRSHLD,NUMCONV)
  IF (NUMCONV) THEN
! Convergence reached
     ! CALL OUTPUT_FINALIZE(ITER,PDM,PHI,NBAST,EIG,EIGVEC,ETOT)
     GO TO 2
  ELSE IF (ITER==1000*MAXITR+200) THEN
! Maximum number of iterations reached without convergence
     GO TO 5
  ELSE
! Convergence not reached, increment
     ETOT1=ETOT
     GO TO 7
  END IF
END SUBROUTINE
