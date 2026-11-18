import javafx.application.Application;

public final class ApplicationWithMain extends DirectApplication {
    public static void main(String[] args) {
        System.out.println("APPLICATION_MAIN");
        Application.launch(ApplicationWithMain.class, args);
    }
}
