#include <SDL2/SDL.h>

#include "configuration.h"
#include "dataset_loader.h"
#include "rendering.h"

extern dataset_t dataset;

// Constants for rendering.
static const int kCellWidth = 4;

// SDL rendering variables.
SDL_Window* window = nullptr;
SDL_Renderer* renderer = nullptr;

static void render_rect(SDL_Renderer* renderer, int x, int y, char state) {
  if (state == 1) {
    SDL_Rect rect;
    rect.w = rect.h = kCellWidth;
    rect.x = x*kCellWidth;
    rect.y = y*kCellWidth;
    SDL_RenderDrawRect(renderer, &rect);
  }
}


// Render simulation. Return value indicates if similation should continue.
void draw(char* host_cells) {
  // Clear scene.
  SDL_SetRenderDrawColor(renderer, 255, 255, 255, SDL_ALPHA_OPAQUE);
  SDL_RenderClear(renderer);
  SDL_SetRenderDrawColor(renderer, 0, 0, 0, SDL_ALPHA_OPAQUE);

  // Draw all bodies.
  for (int i = 0; i < dataset.x*dataset.y; ++i) {
    render_rect(renderer, i%dataset.x, i/dataset.x, host_cells[i]);
  }

  SDL_RenderPresent(renderer);

  // Continue until the user closes the window.
  SDL_Event event;
  while (SDL_PollEvent(&event)) {
    if (event.type == SDL_QUIT) {
      exit(1);
    }
  }

  SDL_Delay(50);
}


void init_renderer() {
  // Initialize graphical output.
  if (SDL_Init(SDL_INIT_VIDEO) != 0) {
    printf("Could not initialize SDL!\n");
    exit(1);
  }

  if (SDL_CreateWindowAndRenderer(kCellWidth*dataset.x, kCellWidth*dataset.y,
        0, &window, &renderer) != 0) {
    printf("Could not create window/render!\n");
    exit(1);
  }
}


void close_renderer() {
  SDL_DestroyRenderer(renderer);
  SDL_DestroyWindow(window);
  SDL_Quit();
}

