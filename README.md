# demoEJB_Stateless — the smallest useful EJB

A single `@Stateless` session bean, called through a JAX-RS endpoint with `@EJB` injection.
No interfaces, no XML wiring, no `new`. Deployed as a plain WAR on **JBoss EAP 8.0 (Jakarta EE 10)**.

```
Browser / curl
      │  HTTP GET /demoEJB-Stateless/api/checkout?price=100
      ▼
CheckoutResource            (JAX-RS, @Path("/checkout"))
      │  @EJB  →  container-injected proxy
      ▼
TaxCalculatorBean           (@Stateless — pooled, transactional, container-managed)
      │
      └─ return price + price*rate
```

| File | Role |
|---|---|
| `src/main/java/com/example/service/TaxCalculatorBean.java` | The EJB. `@Stateless` + business method + lifecycle callbacks. |
| `src/main/java/com/example/web/CheckoutResource.java` | The client. `@EJB` field, `@GET` endpoint. |
| `src/main/java/com/example/web/RestApplication.java` | `@ApplicationPath("/api")` — turns JAX-RS on. |
| `src/main/webapp/WEB-INF/beans.xml` | Marks the WAR as a bean archive (CDI active). |
| `src/main/webapp/index.html` | Little click-through page that calls the endpoint. |
| `scripts/verify.sh` | Ad-hoc verifier: rebuild → redeploy → 24 assertions (build, WAR contents, maths, pool id, log evidence). |
| `pom.xml` | WAR packaging, `jakarta.jakartaee-api:10.0.0` **provided**. |

---

## 1. Run it

Prerequisites already on this machine:

- JDK 17 — `C:\Program Files\Java\jdk-17.0.18` (⚠ your `JAVA_HOME` on the machine points at **JDK 8**, which EAP 8 cannot run on — the scripts below override it)
- Maven 3.9.16 — `D:\APPS_EJB_20261119\tools\apache-maven-3.9.16`
- JBoss EAP 8.0 — `D:\Download\jboss-eap-8.0.0\jboss-eap-8.0`

**Two windows (cmd.exe, not PowerShell needed):**

```bat
:: window 1 — the server
D:\APPS_EJB_20261119\demoEJB_Stateless\scripts\start-server.bat
```

Wait for `WFLYSRV0025: JBoss EAP 8.0.0.GA started in ...ms`, then:

```bat
:: window 2 — build + deploy
D:\APPS_EJB_20261119\demoEJB_Stateless\scripts\deploy.bat
```

Then open **http://localhost:8080/demoEJB-Stateless/**

Manual equivalent, if you prefer:

```bash
export JAVA_HOME='C:\Program Files\Java\jdk-17.0.18'

# build
cd /d/APPS_EJB_20261119/demoEJB_Stateless
/d/APPS_EJB_20261119/tools/mvn.sh clean package

# deploy (hot-deploy: the scanner picks the file up)
cp target/demoEJB-Stateless.war /d/Download/jboss-eap-8.0.0/jboss-eap-8.0/standalone/deployments/
```

| URL | What |
|---|---|
| `http://localhost:8080/demoEJB-Stateless/` | the click-through page |
| `http://localhost:8080/demoEJB-Stateless/api/checkout?price=100` | JSON result, default 8% |
| `http://localhost:8080/demoEJB-Stateless/api/checkout?price=100&rate=0.20` | 20% |
| `D:\Download\jboss-eap-8.0.0\jboss-eap-8.0\standalone\log\server.log` | the EJB container log |

Undeploy: delete `standalone\deployments\demoEJB-Stateless.war` (and its `.deployed` marker). Hot deploy works both ways.

> **Note on this particular server install**: `standalone.xml` already contains an unrelated embedded
> deployment (`interior-design.war`) and an Oracle datasource pointing at `localhost:1521`, which is
> not running — that is why startup ends with *"started (with errors) ... 3 services failed"*. Neither
> affects this demo. Log lines for our bean are tagged `[TaxCalculatorBean]`.


---

## 2. The three lines that matter

```java
@Stateless                                  // ① hand the class to the container
public class TaxCalculatorBean { ... }

@EJB private TaxCalculatorBean taxCalculator;   // ② container injects a proxy

double total = taxCalculator.calculateTotalWithTax(price, 0.08);   // ③ goes through the proxy
```

`taxCalculator` is **not** the bean object. It is a generated proxy. When you invoke a method on it:

1. the call lands in the EJB container,
2. the container picks a free instance from the **pool** (creating one if the pool is empty),
3. it opens a **JTA transaction** (default `@TransactionAttribute(REQUIRED)` — transaction started if none exists, joined if there is one),
4. it runs your method,
5. it commits (or rolls back on a *runtime* exception),
6. it puts the instance back in the pool.

You wrote step 4. Steps 1–3, 5, 6 are the whole point of EJB.

---

## 3. What to look for in `server.log`

Every call prints two lines:

```
[TaxCalculatorBean] @PostConstruct  instanceId=5f2a91b3
[TaxCalculatorBean] calculateTotalWithTax(price=100.0, rate=0.08) served by instanceId=5f2a91b3
```

Press the button 20 times: `instanceId` normally stays the same, because the default stateless pool
starts small (`derive-size` from the CPU count, minimum 1 in practice per deployment). The bean is
reused, so **you must never keep per-user state in a field of a `@Stateless` bean** — the next
request may land on a different instance. That is exactly what `@Stateful` is for.

`@PostConstruct` fires once per *instance creation*, not once per request. `@PreDestroy` fires when
the container discards the instance, which may be at undeploy — **not** at the end of the HTTP request.

---

## 4. Gotchas worth knowing now

| Symptom | Cause |
|---|---|
| `ClassNotFoundException: javax.ejb.Stateless` | Java EE 8/javax project. Modern code uses `jakarta.ejb.*`. Don't mix `javax` and `jakarta` jars. |
| `NullPointerException` on the `@EJB` field | The class was created with `new`, or the class is not a bean (no `@Stateless`), or injection happened in a non-container-managed object. |
| 404 on `/api/checkout` | Missing `RestApplication` (`@ApplicationPath`), or wrong context root — check the WAR name. |
| `@EJB` works but `@Inject` does not | WAR has no `beans.xml` in EE 10 packaging, or the class is not in a bean archive. |
| Transaktion does nothing | No datasource/JPA in this demo: a JTA transaction here has nothing to commit. Add JPA to *see* rollback. |
| EAR vs WAR | Here the WAR *is* the EJB module. Use an EAR (ejb jar + war) when you want remote interfaces or multiple modules. |
| `curl` returns **HTTP 200 with an empty body**, right after a redeploy | Not a bug in your code. Hot redeploy = `WFLYUT0022 Unregistered web context` → `WFLYUT0021 Registered`, and during that ~1s gap Undertow answers 200 with zero bytes. Never treat a 200 as "ready": poll for expected *content*. Also note the `.deployed` marker is written **before** the context comes back, and deleting a marker file is a scanner *command* (undeploy), not cleanup. |

**`@EJB` vs `@Inject`** — both work here. `@EJB` is the EJB-specific injection point (gives you the
EJB proxy). `@Inject` is CDI, and CDI resolves an EJB as a bean too. Use `@EJB` when you want to
make it obvious in the code that this is an EJB.

---

## 5. Next steps

- **`@Stateful` + `@Remove`** — a shopping cart that remembers the user between calls (needs a stateful session or a client-held reference).
- **`@Singleton` + `@Startup`** — one instance for the app, `@Lock` for concurrency, `@Schedule` for timers.
- **`@MessageDriven`** — an async JMS consumer; the container drives the loop.
- **JPA + JTA** — add a datasource and watch a transaction roll back for real.
- **`@TransactionAttribute`** — `NOT_SUPPORTED`, `REQUIRES_NEW`, `MANDATORY` and how they nest.

A bigger worked example with all of these lives in `D:\APPS_EJB\ejb-learning\`.
"# demoEJB_Stateless" 
