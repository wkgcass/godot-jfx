import javafx.application.Application;

public final class ShadowMain {
    public static void main(String[] args) {
        System.out.println("APPLICATION_PID=" + ProcessHandle.current().pid());
        if (args.length == 0) {
            Application.launch(StageApplication.class);
        } else if ("view".equals(args[0])) {
            System.setProperty("test.input", "true");
            Application.launch(DirectApplication.class);
        } else {
            throw new IllegalArgumentException(args[0]);
        }
    }
}
