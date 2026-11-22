package com.spkd.tinycrm.tinyos.config;

import com.spkd.tinycrm.tinyos.entity.User;
import com.spkd.tinycrm.tinyos.service.AuthenticationService;
import com.spkd.tinycrm.tinyos.service.UserService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

@Component
public class DataInitializer implements CommandLineRunner {

    @Autowired
    private UserService userService;
    
    @Autowired
    private AuthenticationService authenticationService;

    // [SD] Cada cliente tiene sus propios usuarios iniciales (admin_a, admin_b...)
    @Value("${app.tenant.id}")
    private String tenant;

    @Value("${app.tenant.dominio}")
    private String dominio;

    @Override
    public void run(String... args) throws Exception {
        final String sufijo = tenant.toLowerCase();
        final String usernameAdmin = "admin_" + sufijo;
        final String usernameSupport = "support_" + sufijo;
        // Create default admin user if it doesn't exist
        if (!userService.existsByUsername(usernameAdmin)) {
            try {
                User adminUser = new User();
                adminUser.setUsername(usernameAdmin);
                adminUser.setEmail("admin@" + dominio);
                adminUser.setPassword("admin123"); // This will be hashed by the service
                adminUser.setFirstName("System");
                adminUser.setLastName("Administrator");
                adminUser.setRole(User.Role.ADMIN);
                adminUser.setActive(true);
                
                authenticationService.registerUser(adminUser);
                System.out.println("Default admin user created successfully");
                System.out.println("Username: " + usernameAdmin);
                System.out.println("Password: admin123");
                System.out.println("Please change the password after first login");
            } catch (Exception e) {
                System.err.println("Error creating default admin user: " + e.getMessage());
            }
        }
        
        // Create a sample support user
        if (!userService.existsByUsername(usernameSupport)) {
            try {
                User supportUser = new User();
                supportUser.setUsername(usernameSupport);
                supportUser.setEmail("support@" + dominio);
                supportUser.setPassword("support123");
                supportUser.setFirstName("Support");
                supportUser.setLastName("Agent");
                supportUser.setRole(User.Role.SUPPORT);
                supportUser.setActive(true);
                
                authenticationService.registerUser(supportUser);
                System.out.println("Default support user created successfully");
                System.out.println("Username: " + usernameSupport);
                System.out.println("Password: support123");
            } catch (Exception e) {
                System.err.println("Error creating default support user: " + e.getMessage());
            }
        }
    }
}
