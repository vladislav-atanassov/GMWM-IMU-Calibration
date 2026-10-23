/**
  ******************************************************************************
  * @file    app.h
  * @brief   Application entry points, called from main.c.
  ******************************************************************************
  */
#ifndef APP_H
#define APP_H

#ifdef __cplusplus
extern "C" {
#endif

/* Call once, after the CubeMX MX_*_Init() functions */
void app_start(void);

/* Call continuously from the main loop */
void app_poll(void);

#ifdef __cplusplus
}
#endif

#endif /* APP_H */
