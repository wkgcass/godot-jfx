/** Keeps the host active without FX rendering; the host fixture owns its FPS cap. */
public final class PacingCapProbe {
    public static void main(String[] args) throws InterruptedException {
        Thread.sleep(6500);
        System.out.println("PACING_CAP_JAVA_PASS");
    }
}
