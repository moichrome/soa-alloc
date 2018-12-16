#ifndef EXAMPLE_SUGARSCAPE_SOA_CONFIGURATION_H
#define EXAMPLE_SUGARSCAPE_SOA_CONFIGURATION_H

// Size of simulation.
static const int kSize = 1000;
static const int kSeed = 42;

// For initialization only.
static const float kProbMale = 0.12;
static const float kProbFemale = 0.15;

// Simulation constants.
static const int kNumIterations = 500;
static const int kMaxVision = 2;
static const int kMaxAge = 100;
static const int kMaxEndowment = 200;
static const int kMaxMetabolism = 80;
static const int kSugarCapacity = 5000;
static const int kMaxSugarDiffusion = 100;
static const float kSugarDiffusionRate = 0.10;
static const int kMaxGrowRate = 50;

// Debug/rendering
static const bool kOptionRender = false;
static const int kWithoutAgents = true;

#endif  // EXAMPLE_SUGARSCAPE_SOA_CONFIGURATION_H
