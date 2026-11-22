package com.spkd.tinycrm.tinyos.service;

import com.spkd.tinycrm.tinyos.entity.User;
import com.spkd.tinycrm.tinyos.eventos.UsuarioEvento;
import com.spkd.tinycrm.tinyos.eventos.UsuarioEventoFactory;
import com.spkd.tinycrm.tinyos.repository.UserRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;

@Service
public class UserService {

    @Autowired
    private UserRepository userRepository;

    // [SD] Crear usuarios siempre por el mismo camino (hash + evento)
    @Autowired
    private AuthenticationService authenticationService;

    @Autowired
    private ApplicationEventPublisher eventPublisher;

    @Autowired
    private UsuarioEventoFactory eventoFactory;

    public List<User> getAllUsers() {
        return userRepository.findAll();
    }

    public Optional<User> getUserById(Long id) {
        return userRepository.findById(id);
    }

    public User createUser(User user) {
        // [SD] Antes guardaba la clave sin hash; ahora usa registerUser,
        // que ademas publica el evento USUARIO_CREADO
        return authenticationService.registerUser(user);
    }

    public User updateUser(Long id, User user) {
        if (userRepository.existsById(id)) {
            Optional<User> existingUserOpt = userRepository.findById(id);
            if (existingUserOpt.isPresent()) {
                User existingUser = existingUserOpt.get();
                
                // Update only non-null fields
                if (user.getFirstName() != null) existingUser.setFirstName(user.getFirstName());
                if (user.getLastName() != null) existingUser.setLastName(user.getLastName());
                if (user.getEmail() != null) existingUser.setEmail(user.getEmail());
                if (user.getRole() != null) existingUser.setRole(user.getRole());
                
                return userRepository.save(existingUser);
            }
            return null;
        } else {
            return null;
        }
    }

    public void deleteUser(Long id) {
        Optional<User> existente = userRepository.findById(id);
        userRepository.deleteById(id);
        // [SD] Retirar al usuario del registro central
        existente.ifPresent(u -> eventPublisher.publishEvent(eventoFactory.desde(UsuarioEvento.ELIMINADO, u)));
    }
    
    public Optional<User> findByUsername(String username) {
        return userRepository.findByUsername(username);
    }
    
    public Optional<User> findByEmail(String email) {
        return userRepository.findByEmail(email);
    }
    
    public boolean existsByUsername(String username) {
        return userRepository.existsByUsername(username);
    }
    
    public boolean existsByEmail(String email) {
        return userRepository.existsByEmail(email);
    }
    
    // Additional methods for profile management
    public Optional<User> findById(Long id) {
        return userRepository.findById(id);
    }
    
    public User save(User user) {
        return userRepository.save(user);
    }
}
