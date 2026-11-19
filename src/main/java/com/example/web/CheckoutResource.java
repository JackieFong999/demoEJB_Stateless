package com.example.web;

import com.example.service.TaxCalculatorBean;
import jakarta.ejb.EJB;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;

/**
 * 2) THE CLIENT.
 *
 * This is a JAX-RS resource. It never does "new TaxCalculatorBean()".
 * The container injects a managed reference (a proxy) and the call travels
 * through the EJB container.
 */
@Path("/checkout")
public class CheckoutResource {

    /**
     * @EJB injection. The field you get is not the bean itself 
     *                 — it is a container proxy. Two alternatives that also work here:
     *
     *   @Inject  TaxCalculatorBean taxCalculator;      // CDI style (also works)
     *   @Resource ...                                  // plain JNDI lookup
     */
    @EJB
    private TaxCalculatorBean taxCalculator;

    /**
     * GET /api/checkout?price=100
     * GET /api/checkout?price=100&rate=0.08
     */
    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public String getFinalPrice(@QueryParam("price") @DefaultValue("100") double price,
                               @QueryParam("rate") @DefaultValue("0.08") double rate) {

        double total = taxCalculator.calculateTotalWithTax(price, rate);

        return "{"
                + "\"price\":" + price + ","
                + "\"taxRate\":" + rate + ","
                + "\"tax\":" + (total - price) + ","
                + "\"total\":" + total + ","
                + "\"servedByBeanInstance\":\"" + taxCalculator.getInstanceId() + "\""
                + "}";
    }
}
