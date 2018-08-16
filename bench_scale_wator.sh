#!/bin/bash
# Tested using bash version 4.1.5
for ((i=2843;i<=4096;i+=8)); 
do 
  echo ${i}

#  /usr/local/cuda/bin/nvcc -std=c++11 -DGRID_SIZE_Y=${i} -O3 -use_fast_math wa-tor/aos/wator_mallocmc.cu -I. -Imallocmc_copy/src/include -arch compute_61
#  ./a.out >> bench_wator_scale_mallocmc.csv
#  echo "MALLOCMC"
#  cat bench_wator_scale_mallocmc.csv

  /usr/local/cuda/bin/nvcc -std=c++11 -DGRID_SIZE_Y=${i} -O3 -use_fast_math wa-tor/aos/wator_aos.cu -I. -arch compute_61
  ./a.out >> bench_wator_scale_aos.csv

  echo "AOS"
  cat bench_wator_scale_aos.csv

  /usr/local/cuda/bin/nvcc -std=c++11 -DGRID_SIZE_Y=${i} -O3 -use_fast_math wa-tor/aos/wator_soa.cu -I. -arch compute_61
  ./a.out >> bench_wator_scale_soa.csv

  echo "SOA"
  cat bench_wator_scale_soa.csv


#  /usr/local/cuda/bin/nvcc -std=c++11 -DGRID_SIZE_Y=${i} -O3 -use_fast_math wa-tor/aos/wator.cu -I. -arch compute_61
#  ./a.out >> bench_wator_scale_cuda.csv

#  echo "CUDA"
#  cat bench_wator_scale_cuda.csv


#  /usr/local/cuda/bin/nvcc -std=c++11 -DGRID_SIZE_Y=${i} -O3 -use_fast_math wa-tor/aos/wator_halloc.cu -I. -I/home/matthias/halloc/install/include -dc -arch compute_61 -o wator.o
#  /usr/local/cuda/bin/nvcc -std=c++11 -O3 -use_fast_math -arch compute_61 -L/home/matthias/halloc/install/lib -lhalloc -o wator wator.o
#  ./wator >> bench_wator_scale_halloc.csv
#echo "HALLOC"
#cat bench_wator_scale_halloc.csv

done
