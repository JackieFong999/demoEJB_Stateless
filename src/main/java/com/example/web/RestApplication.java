package com.example.web;

import jakarta.ws.rs.ApplicationPath;
import jakarta.ws.rs.core.Application;

/**
 * 3) THE GLUE.
 *
 * Without this class the JAX-RS endpoints are never activated. @ApplicationPath
 * sets the base URI for every @Path in the app -> everything lives under /api.
 *
 * Full URL: http://localhost:8080/demoEJB-Stateless/api/checkout?price=100
 */
@ApplicationPath("/api")
public class RestApplication extends Application {
}
