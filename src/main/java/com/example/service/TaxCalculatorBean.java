package com.example.service;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import jakarta.ejb.Stateless;

/**
 * 1) THE EJB.
 *
 * A plain Java class + @Stateless. Nothing else is required: no interfaces,
 * no XML, no "new". The EJB container creates a POOL of these instances and
 * decides which pooled instance serves each call.
 *
 * What the container adds around every business method call:
 *   - lifecycle + pooling            (this is a pooled, reusable worker)
 *   - transaction (default: REQUIRED -> starts a JTA transaction if none is open)
 *   - security, thread-safety        (one call per instance at a time)
 *   - the proxy that @EJB hands to clients
 *
 * Location here (inside a WAR) is deliberate: the WAR *is* the EJB module.
 */
@Stateless
public class TaxCalculatorBean {

    // Not a business concern — just so you can see the pooling in the log.
    private String instanceId;

    /**
     * Container callback: runs once per instance, right after the container
     * creates it and before it serves any request. Not called by you.
     */
    @PostConstruct
    void init() {
        instanceId = Integer.toHexString(System.identityHashCode(this));
        System.out.println("[TaxCalculatorBean] @PostConstruct  instanceId=" + instanceId);
    }

    /**
     * Container callback: runs when the container throws the instance away
     * (pool shrink / shutdown). Note this is NOT "end of request".
     */
    @PreDestroy
    void destroy() {
        System.out.println("[TaxCalculatorBean] @PreDestroy     instanceId=" + instanceId);
    }

    /** Which pooled instance answered — proves the bean is container-managed. */
    public String getInstanceId() {
        return instanceId;
    }
    
    /**
     * The business logic. Notice: no transaction code, no try/catch, no logging
     * framework, no "close". The container wraps this method.
     *
     * @param price    net price
     * @param taxRate  e.g. 0.08 for 8%
     * @return price + tax
     */
    public double calculateTotalWithTax(double price, double taxRate) {
        System.out.println("[TaxCalculatorBean] calculateTotalWithTax(price=" + price
                + ", rate=" + taxRate + ") served by instanceId=" + instanceId);
        return price + (price * taxRate);
    }


}
